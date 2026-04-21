package Gtk3::FzfWidget::Process ;

use strict ;
use warnings ;
use POSIX qw(setsid WNOHANG _exit) ;
use Encode qw(encode_utf8 is_utf8) ;
use IO::Pty ;
use IO::Socket::INET ;
use Glib ;
use Gtk3::FzfWidget::Client ;
use Gtk3::FzfWidget::ItemWriter ;
use Gtk3::FzfWidget::StatePoller ;
use Gtk3::FzfWidget::Messages qw(msg
	MSG_FZF_NOT_FOUND
	MSG_VERSION_TOO_OLD
	MSG_VERSION_PARSE
	MSG_PROCESS_FAILED
	MSG_PROCESS_RESTART
	MSG_PROCESS_GIVE_UP
	MSG_OPT_CONFLICT
	MSG_EXIT_CODE) ;

our $VERSION = '0.01' ;

my $MIN_VERSION   = '0.65.0' ;
my $DEATH_POLL_MS = 500 ;
my $RESTART_DELAY = 500 ;
my $MAX_RESTARTS  = 3 ;
my $instance_seq  = 0 ;

my @CONFLICTING_OPTS = qw(--height --tmux --tty --no-tty) ;

# ------------------------------------------------------------------------------

sub _free_port
{
my $sock = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1',
	LocalPort => 0,
	Proto     => 'tcp',
	ReuseAddr => 1,
	) or die "cannot bind to get free port: $!" ;

my $port = $sock->sockport() ;
$sock->close() ;

return $port ;
}

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;

my $config = $args{config} // {} ;
my $id     = ++$instance_seq ;

my $port = $config->{port} ;
$port    = _free_port() unless defined $port ;

my $self =
	{
	items          => $args{items}              // [],
	fzf_opts       => $config->{fzf_opts}       // [],
	ansi           => $config->{ansi}           // 0,
	port           => $port,
	start_delay_ms => $config->{start_delay_ms} // 100,
	multi          => $config->{multi}          // 0,
	on_ready       => $args{on_ready},
	on_error       => $args{on_error},
	instance_id    => $id,
	pid            => undef,
	pty            => undef,
	client         => undef,
	poller         => undef,
	writer         => undef,
	restart_count  => 0,
	current_query  => '',
	death_watch    => undef,
	start_timer    => undef,
	_stopping      => 0,
	} ;

return bless $self, $class ;
}

# ------------------------------------------------------------------------------

sub check_fzf_version
{
my ($class) = @_ ;

my $output = `fzf --version 2>&1` ;

unless ($output)
	{
	return (0, msg(MSG_FZF_NOT_FOUND)) ;
	}

chomp $output ;
my ($ver) = $output =~ /^(\d+\.\d+\.\d+)/ ;

unless ($ver)
	{
	return (0, msg(MSG_VERSION_PARSE, $output)) ;
	}

if (_version_lt($ver, $MIN_VERSION))
	{
	return (0, msg(MSG_VERSION_TOO_OLD, $ver, $MIN_VERSION)) ;
	}

return (1, $ver) ;
}

# ------------------------------------------------------------------------------

sub _version_lt
{
my ($a, $b) = @_ ;

my @a = split(/\./, $a) ;
my @b = split(/\./, $b) ;

for my $i (0 .. 2)
	{
	return 1 if ($a[$i] // 0) < ($b[$i] // 0) ;
	return 0 if ($a[$i] // 0) > ($b[$i] // 0) ;
	}

return 0 ;
}

# ------------------------------------------------------------------------------

sub _check_conflicting_opts
{
my ($self) = @_ ;

for my $opt (@{$self->{fzf_opts}})
	{
	for my $bad (@CONFLICTING_OPTS)
		{
		next unless index($opt, $bad) == 0 ;

		my $m = msg(MSG_OPT_CONFLICT, $opt) ;
		warn $m ;
		print STDERR $m . "\n" ;
		}
	}
}

# ------------------------------------------------------------------------------

sub start
{
my ($self, $query) = @_ ;

$self->{current_query} = $query // $self->{current_query} ;
$self->{_stopping}     = 0 ;

$self->_check_conflicting_opts() ;

my @cmd = $self->_build_cmd() ;

unless ($self->_spawn(@cmd))
	{
	$self->_handle_failure(msg(MSG_PROCESS_FAILED, 'spawn failed')) ;

	return ;
	}

$self->{start_timer} = Glib::Timeout->add(
	$self->{start_delay_ms},
	sub
		{
		$self->{start_timer} = undef ;

		$self->{client} = Gtk3::FzfWidget::Client->new(
			port => $self->{port},
			) ;

		$self->{poller} = Gtk3::FzfWidget::StatePoller->new(
			port => $self->{port},
			) ;

		$self->{on_ready}->($self) if $self->{on_ready} ;

		return 0 ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub _spawn
{
my ($self, @cmd) = @_ ;

$self->_cleanup_watches() ;

pipe(my $in_r, my $in_w) or return 0 ;

my $pty = IO::Pty->new() ;

unless ($pty)
	{
	my $m = msg(MSG_PROCESS_FAILED, "pty: $!") ;
	warn $m ;
	print STDERR $m . "\n" ;

	return 0 ;
	}

my $pid = fork() ;

unless (defined $pid)
	{
	my $m = msg(MSG_PROCESS_FAILED, "fork: $!") ;
	warn $m ;
	print STDERR $m . "\n" ;

	return 0 ;
	}

if ($pid == 0)
	{
	$pty->make_slave_controlling_terminal() ;
	my $slave = $pty->slave() ;

	close $in_w ;

	POSIX::dup2(fileno($in_r), 0) ;
	close $in_r ;

	open(my $devnull, '>', '/dev/null') or _exit(1) ;
	POSIX::dup2(fileno($devnull), 1) ;
	POSIX::dup2(fileno($devnull), 2) ;
	close $devnull ;
	close $slave ;

	{ no warnings 'exec' ; exec @cmd }
	_exit(1) ;
	}

close $in_r ;

# Fork a writer child to stream items to fzf asynchronously.
# This returns immediately — the GTK main loop is never blocked.
my $writer = Gtk3::FzfWidget::ItemWriter->new(
	items => $self->{items},
	fh    => $in_w,
	) ;

$writer->start() ;

$self->{writer} = $writer ;
$self->{pid}    = $pid ;
$self->{pty}    = $pty ;

$self->_watch_death() ;

return 1 ;
}

# ------------------------------------------------------------------------------

sub _watch_death
{
my ($self) = @_ ;

# DEATH_POLL_MS: GTK's main loop does not deliver SIGCHLD reliably to Perl
# signal handlers — the signal may arrive while GTK is in C code and get lost.
# waitpid(WNOHANG) in a timer is the standard workaround to reap child
# processes without blocking.
$self->{death_watch} = Glib::Timeout->add(
	$DEATH_POLL_MS,
	sub
		{
		return 0 unless $self->{pid} ;

		# Reap writer child if it has finished
		$self->{writer}->reap() if $self->{writer} ;

		my $result = waitpid($self->{pid}, WNOHANG) ;

		if ($result == $self->{pid})
			{
			my $status = $? ;
			$self->{pid}         = undef ;
			$self->{death_watch} = undef ;

			$self->_on_child_exit($status) unless $self->{_stopping} ;

			return 0 ;
			}

		return 1 ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub _on_child_exit
{
my ($self, $waitstatus) = @_ ;

return if $self->{_stopping} ;

my $code = $waitstatus >> 8 ;
$self->_handle_failure(msg(MSG_EXIT_CODE, $code)) ;
}

# ------------------------------------------------------------------------------

sub _handle_failure
{
my ($self, $reason) = @_ ;

return if $self->{_stopping} ;

$self->{restart_count}++ ;

if ($self->{restart_count} <= $MAX_RESTARTS)
	{
	my $m = msg(MSG_PROCESS_RESTART, $self->{restart_count}, $MAX_RESTARTS) ;
	warn $m ;
	print STDERR $m . "\n" ;

	Glib::Timeout->add(
		$RESTART_DELAY,
		sub
			{
			$self->start($self->{current_query}) ;

			return 0 ;
			},
		) ;
	}
else
	{
	my $m = msg(MSG_PROCESS_GIVE_UP, $MAX_RESTARTS, $reason) ;
	warn $m ;
	print STDERR $m . "\n" ;

	$self->{on_error}->($m) if $self->{on_error} ;
	}
}

# ------------------------------------------------------------------------------

sub _build_cmd
{
my ($self) = @_ ;

my @cmd = ('fzf', "--listen=$self->{port}") ;
push @cmd, '--multi' if $self->{multi} ;
push @cmd, '--ansi'  if $self->{ansi} ;
push @cmd, @{$self->{fzf_opts}} ;

return @cmd ;
}

# ------------------------------------------------------------------------------

sub _cleanup_watches
{
my ($self) = @_ ;

for my $field (qw(start_timer death_watch))
	{
	if ($self->{$field})
		{
		Glib::Source->remove($self->{$field}) ;
		$self->{$field} = undef ;
		}
	}

if ($self->{pty})
	{
	$self->{pty}->close() ;
	$self->{pty} = undef ;
	}

if ($self->{client})
	{
	$self->{client}->disconnect() ;
	$self->{client} = undef ;
	}

if ($self->{poller})
	{
	$self->{poller}->disconnect() ;
	$self->{poller} = undef ;
	}
}

# ------------------------------------------------------------------------------

sub stop
{
my ($self) = @_ ;

$self->{_stopping} = 1 ;

$self->_cleanup_watches() ;

if ($self->{writer})
	{
	$self->{writer}->stop() ;
	$self->{writer} = undef ;
	}

if ($self->{pid})
	{
	kill 'TERM', $self->{pid} ;
	$self->{pid} = undef ;
	}
}

# ------------------------------------------------------------------------------

sub set_items
{
my ($self, $items, $query) = @_ ;

$self->{items}         = $items ;
$self->{restart_count} = 0 ;

$self->stop() ;

Glib::Timeout->add(
	100,
	sub
		{
		$self->start($query) ;

		return 0 ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub reset_restart_count { $_[0]->{restart_count} = 0 }

# ------------------------------------------------------------------------------

sub get_state_async
{
my ($self, $limit, $cb) = @_ ;

return $cb->(undef) unless $self->{poller} ;
$self->{poller}->get_state($limit, $cb) ;
}

# ------------------------------------------------------------------------------

sub get_more_async
{
my ($self, $offset, $limit, $cb) = @_ ;

return $cb->([]) unless $self->{poller} ;
$self->{poller}->get_more($offset, $limit, $cb) ;
}

# ------------------------------------------------------------------------------

sub get_state
{
my ($self, $limit) = @_ ;

return undef unless $self->{client} ;

my $state = $self->{client}->get_state($limit) ;
$self->reset_restart_count() if $state ;

return $state ;
}

# ------------------------------------------------------------------------------

sub get_more_matches
{
my ($self, $offset) = @_ ;

return undef unless $self->{client} ;

return $self->{client}->get_more_matches($offset) ;
}

# ------------------------------------------------------------------------------

sub cancel
{
my ($self) = @_ ;
$self->{poller}->cancel() if $self->{poller} ;
}

# ------------------------------------------------------------------------------

sub post_sync
{
my ($self, $action) = @_ ;

return unless $self->{poller} ;
$self->{poller}->post_sync($action) ;
}

# ------------------------------------------------------------------------------

sub post_action
{
my ($self, $action) = @_ ;

return 0 unless $self->{poller} ;

$self->{poller}->post_action($action) ;
return 1 ;
}

1 ;
