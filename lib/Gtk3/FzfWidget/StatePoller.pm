package Gtk3::FzfWidget::StatePoller ;

# Non-blocking fzf state poller.
#
# Problem: fzf's HTTP server can take seconds to respond when busy indexing
# large datasets. Calling get_state() synchronously blocks the GTK main loop,
# causing the UI to freeze and keyboard events to queue up.
#
# Solution: run each HTTP request in a forked child process. The child writes
# the JSON response to a pipe; a Glib IO watch reads it when ready without
# blocking the main loop. The caller registers a callback that fires when the
# result arrives.
#
# Usage:
#   my $poller = Gtk3::FzfWidget::StatePoller->new(port => $port) ;
#
#   # Request state (non-blocking)
#   $poller->get_state($limit, sub { my ($state) = @_ ; ... }) ;
#
#   # Request more matches (non-blocking)
#   $poller->get_more($offset, $limit, sub { my ($matches) = @_ ; ... }) ;
#
# Only one request is outstanding at a time. If a new request arrives while
# one is pending, the pending request is abandoned (its callback is never
# called) and the new one starts.

use strict ;
use warnings ;
use POSIX qw(WNOHANG _exit) ;
use IO::Socket::INET ;
use Glib ;

our $VERSION = '0.01' ;

my $_DEBUG = $ENV{FZFW_DEBUG} ? 1 : 0 ;

if ($_DEBUG)
	{
	binmode(STDERR, ':utf8') ;
	}

sub _dbg_sp
{
my ($self, $msg) = @_ ;
return unless $_DEBUG ;
require Time::HiRes ;
my ($sec, $usec) = Time::HiRes::gettimeofday() ;
printf STDERR "[%.3f] POLLER: %s\n", $sec + $usec / 1e6, $msg ;
}

my $_json_class ;

BEGIN
	{
	$_json_class =
		eval { require JSON::XS        ; 'JSON::XS'        } //
		eval { require Cpanel::JSON::XS ; 'Cpanel::JSON::XS' } //
		do   { require JSON::PP        ; 'JSON::PP'         } ;
	}

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;

my $self =
	{
	host         => $args{host} // '127.0.0.1',
	port         => $args{port},
	json         => $_json_class->new->utf8,
	pid          => undef,
	pipe_r       => undef,
	io_watch     => undef,
	timeout_src  => undef,   # Glib timer id for request timeout
	callback     => undef,
	buf          => '',
	mode         => undef,
	timeout_ms   => $args{timeout_ms} // 2000,
	} ;

return bless $self, $class ;
}

# ------------------------------------------------------------------------------
# Request fzf state.  Calls $cb->($state_hashref) when done, or $cb->(undef)
# on error.

sub get_state
{
my ($self, $limit, $cb) = @_ ;
$limit //= 1 ;
$self->_request("/?limit=$limit&offset=0", $cb, 'json') ;
}

# ------------------------------------------------------------------------------
# Request additional matches from offset.  Calls $cb->(\@matches) when done.

sub get_more
{
my ($self, $offset, $limit, $cb) = @_ ;
$limit //= 50 ;
$self->_request("/?limit=$limit&offset=$offset", $cb, 'matches') ;
}

# ------------------------------------------------------------------------------
# Post an action (fire-and-forget, still async but we don't care about result).

sub post_action
{
my ($self, $action) = @_ ;

# Post actions are fast (fzf always responds immediately) — fork a child
# just to avoid blocking, but don't bother reading the response.
my $pid = fork() ;
return unless defined $pid ;

if ($pid == 0)
	{
	my $sock = IO::Socket::INET->new(
		PeerHost => $self->{host},
		PeerPort => $self->{port},
		Proto    => 'tcp',
		Timeout  => 1,
		) ;

	if ($sock)
		{
		my $body = $action ;
		my $len  = length($body) ;
		my $req  =
			"POST / HTTP/1.1\r\n"
			. "Host: localhost\r\n"
			. "Content-Length: $len\r\n"
			. "Connection: close\r\n"
			. "\r\n"
			. $body ;
		eval { print $sock $req } ;
		# Read and discard the response to avoid broken pipe in fzf
		eval { local $/ ; <$sock> } ;
		$sock->close() ;
		}

	_exit(0) ;
	}

# Parent: reap eventually (don't block)
Glib::Timeout->add(200, sub { waitpid($pid, WNOHANG) ; return 0 }) ;
}

# ------------------------------------------------------------------------------

sub cancel
{
my ($self) = @_ ;
$self->_cancel_pending() ;
}

sub disconnect
{
my ($self) = @_ ;
$self->_cancel_pending() ;
}

# ------------------------------------------------------------------------------

sub _request
{
my ($self, $path, $cb, $mode) = @_ ;

# If a request is already in flight, skip this one.
# The bg_poll or the next navigate will retry.
if (defined $self->{pid})
	{
	$self->_dbg_sp("SKIP request path=$path (in-flight pid=$self->{pid})") ;
	return ;
	}

$self->_start_request($path, $cb, $mode) ;
}

# ------------------------------------------------------------------------------

sub _start_request
{
my ($self, $path, $cb, $mode) = @_ ;

$self->_dbg_sp("START request path=$path mode=$mode") ;

pipe(my $r, my $w) or do { $cb->(undef) ; return } ;

my $pid = fork() ;

unless (defined $pid)
	{
	close $r ;
	close $w ;
	$cb->(undef) ;
	return ;
	}

if ($pid == 0)
	{
	close $r ;

	my $sock = IO::Socket::INET->new(
		PeerHost => $self->{host},
		PeerPort => $self->{port},
		Proto    => 'tcp',
		Timeout  => 5,
		) ;

	unless ($sock)
		{
		close $w ;
		_exit(1) ;
		}

	$sock->autoflush(1) ;

	my $req =
		"GET $path HTTP/1.1\r\n"
		. "Host: localhost\r\n"
		. "Connection: close\r\n"
		. "\r\n" ;

	eval { print $sock $req } ;

	# Skip HTTP headers
	while (my $line = $sock->getline())
		{
		$line =~ s/\r\n$// ;
		last if $line eq '' ;
		}

	# Pipe the response body to the parent
	my $buf ;
	while (defined($buf = $sock->getline()))
		{
		print $w $buf ;
		}

	$sock->close() ;
	close $w ;
	_exit(0) ;
	}

# Parent
close $w ;

$self->{pid}      = $pid ;
$self->{pipe_r}   = $r ;
$self->{callback} = $cb ;
$self->{mode}     = $mode ;
$self->{buf}      = '' ;

# Watch the pipe for data — non-blocking, GTK main loop keeps running.
$self->{io_watch} = Glib::IO->add_watch(
	fileno($r),
	['in', 'hup', 'err'],
	sub
		{
		my ($fd, $condition) = @_ ;
		return $self->_on_pipe_ready($condition) ;
		},
	) ;

# Kill the child if fzf doesn't respond within timeout_ms.
$self->{timeout_src} = Glib::Timeout->add(
	$self->{timeout_ms},
	sub
		{
		$self->_dbg_sp("TIMEOUT after $self->{timeout_ms}ms — killing pid=$self->{pid}") ;
		$self->{timeout_src} = undef ;
		$self->_finish() ;
		return 0 ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub _on_pipe_ready
{
my ($self, $condition) = @_ ;

my $r = $self->{pipe_r} ;

# $condition is a Glib::IOCondition flags object — check with grep on array
# context, not regex which may stringify incorrectly.
my @conds = ref $condition ? @$condition : ($condition) ;
my $has_in  = grep { $_ eq 'in'  } @conds ;
my $has_hup = grep { $_ eq 'hup' } @conds ;
my $has_err = grep { $_ eq 'err' || $_ eq 'nval' } @conds ;

if ($has_in)
	{
	my $chunk = '' ;
	my $n = sysread($r, $chunk, 65536) ;

	if (defined $n && $n > 0)
		{
		$self->{buf} .= $chunk ;
		# If no HUP yet, keep watching for more data.
		return 1 unless $has_hup ;
		# HUP arrived together with in — fall through to finish.
		}
	# n==0 means EOF; undef means error — fall through to finish.
	}

# HUP, ERR, NVAL, or EOF — response complete (or failed).
$self->_finish() ;
return 0 ;
}

# ------------------------------------------------------------------------------

sub _finish
{
my ($self) = @_ ;

my $buf  = $self->{buf} ;
my $cb   = $self->{callback} ;
my $mode = $self->{mode} ;

$self->_clear_watch() ;
$self->_reap_child() ;
$self->{callback} = undef ;
$self->{buf}      = '' ;

$self->_dbg_sp("FINISH mode=$mode buf_len=" . length($buf)) ;

return unless $cb ;

if (!length $buf)
	{
	$cb->(undef) ;
	return ;
	}

my $data = eval { $self->{json}->decode($buf) } ;

if ($@ || !defined $data)
	{
	$cb->(undef) ;
	return ;
	}

if ($mode eq 'matches')
	{
	$cb->($data->{matches} // []) ;
	}
else
	{
	$cb->($data) ;
	}
}

# ------------------------------------------------------------------------------

sub _cancel_pending
{
my ($self) = @_ ;

$self->_clear_watch() ;
$self->{callback} = undef ;
$self->{buf}      = '' ;

if ($self->{pipe_r})
	{
	close $self->{pipe_r} ;
	$self->{pipe_r} = undef ;
	}

$self->_reap_child() ;
}

# ------------------------------------------------------------------------------

sub _clear_watch
{
my ($self) = @_ ;

if ($self->{io_watch})
	{
	Glib::Source->remove($self->{io_watch}) ;
	$self->{io_watch} = undef ;
	}

if ($self->{timeout_src})
	{
	Glib::Source->remove($self->{timeout_src}) ;
	$self->{timeout_src} = undef ;
	}
}

# ------------------------------------------------------------------------------

sub _reap_child
{
my ($self) = @_ ;

if (defined $self->{pid})
	{
	kill 'TERM', $self->{pid} ;
	waitpid($self->{pid}, WNOHANG) ;
	$self->{pid} = undef ;
	}
}

1 ;
