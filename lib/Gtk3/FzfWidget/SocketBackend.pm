package Gtk3::FzfWidget::SocketBackend ;

# FzfBackend implementation over fzf's HTTP API.
# Wraps Gtk3::FzfWidget::Process + StatePoller.

use strict ;
use warnings ;
use POSIX qw(WNOHANG _exit) ;
use IO::Socket::INET ;
use Glib ;

our @ISA = ('Gtk3::FzfWidget::FzfBackend') ;
our $VERSION = '0.01' ;

my $_log_fh ;

sub _log
{
my ($msg) = @_ ;
return unless $ENV{FZFW_DEBUG} || $ENV{FZFW_LOG} ;
require Time::HiRes ;
my ($s, $u) = Time::HiRes::gettimeofday() ;
my $line = sprintf "[%.3f] BACKEND:SOCKET: %s\n", $s + $u/1e6, $msg ;
print STDERR $line if $ENV{FZFW_DEBUG} ;
if ($ENV{FZFW_LOG})
	{
	unless ($_log_fh)
		{
		open($_log_fh, '>>', $ENV{FZFW_LOG}) or return ;
		$_log_fh->autoflush(1) ;
		}
	print $_log_fh $line ;
	}
}

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;
return bless
	{
	process       => $args{process},
	_mc           => 0,
	_tc           => 0,
	_current_query => '',
	}, $class ;
}

# ------------------------------------------------------------------------------

sub total_count { $_[0]->{_tc} }
sub match_count { $_[0]->{_mc} }

# ------------------------------------------------------------------------------

sub query_async
{
my ($self, $query, $limit, $cb) = @_ ;

_log("query_async q='$query' limit=$limit") ;

$self->{_current_query} = $query ;

# post_sync blocked the GTK main loop for up to 2s.
# Instead: fork a child that does the POST synchronously, writes a byte
# to a pipe when done, and the parent watches the pipe to fire the GET.
# This keeps GTK responsive during the POST.

my $process = $self->{process} ;

pipe(my $done_r, my $done_w) or do
	{
	# Fallback: blocking path
	$process->post_sync("change-query($query)") ;
	$process->get_state_async($limit, sub
		{
		my ($state) = @_ ;
		unless ($state)
			{
			_log("query_async: no state returned") ;
			$cb->(undef, 0, 0) ;
			return ;
			}
		$self->{_mc} = $state->{matchCount} // $state->{match_count} // 0 ;
		$self->{_tc} = $state->{totalCount} // $state->{total_count} // 0 ;
		my @matches = map { { index => ($_->{index} // 0), text => ($_->{text} // '') } }
			@{$state->{matches} // []} ;
		$cb->(\@matches, $self->{_mc}, $self->{_tc}) ;
		}) ;
	return ;
	} ;

my $pid = fork() ;

unless (defined $pid)
	{
	close $done_r ; close $done_w ;
	$cb->(undef, 0, 0) ;
	return ;
	}

if ($pid == 0)
	{
	close $done_r ;
	# Child: do the blocking POST, signal parent when done.
	my $sock = IO::Socket::INET->new(
		PeerHost => '127.0.0.1',
		PeerPort => $process->{port},
		Proto    => 'tcp',
		Timeout  => 2,
		) ;
	if ($sock)
		{
		$sock->autoflush(1) ;
		my $action = "change-query($query)" ;
		my $len    = length($action) ;
		my $req    =
			"POST / HTTP/1.1\r\n"
			. "Host: localhost\r\n"
			. "Content-Length: $len\r\n"
			. "Connection: close\r\n"
			. "\r\n"
			. $action ;
		eval { print $sock $req } ;
		eval { local $/ ; my $dummy = <$sock> } ;
		$sock->close() ;
		}
	print $done_w "1" ;
	close $done_w ;
	POSIX::_exit(0) ;
	}

# Parent: watch pipe — fire GET only after POST child signals done.
close $done_w ;

my $watch_id ;
my $buf = '' ;
$watch_id = Glib::IO->add_watch(
	fileno($done_r),
	['in', 'hup'],
	sub
		{
		sysread($done_r, $buf, 1) ;
		Glib::Source->remove($watch_id) ;
		close $done_r ;
		waitpid($pid, POSIX::WNOHANG()) ;

		# If the query changed while we were waiting for the POST,
		# discard — a newer query_async is already in flight.
		return 0 if $self->{_current_query} ne $query ;

		$process->get_state_async($limit, sub
			{
			my ($state) = @_ ;

			unless ($state)
				{
				_log("query_async: no state returned") ;
				$cb->(undef, 0, 0) ;
				return ;
				}

			$self->{_mc} = $state->{matchCount} // $state->{match_count} // 0 ;
			$self->{_tc} = $state->{totalCount} // $state->{total_count} // 0 ;

			my @matches = map
				{ { index => ($_->{index} // 0), text => ($_->{text} // '') } }
				@{$state->{matches} // []} ;

			_log("query_async RESULT: mc=$self->{_mc} tc=$self->{_tc} returned=" . scalar(@matches)) ;
			$cb->(\@matches, $self->{_mc}, $self->{_tc}) ;
			}) ;

		return 0 ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub fetch_async
{
my ($self, $limit, $cb) = @_ ;

_log("fetch_async limit=$limit") ;

$self->{process}->get_state_async($limit, sub
	{
	my ($state) = @_ ;

	unless ($state)
		{
		_log("fetch_async: no state returned") ;
		$cb->(undef, 0, 0) ;
		return ;
		}

	$self->{_mc} = $state->{matchCount} // $state->{match_count} // 0 ;
	$self->{_tc} = $state->{totalCount} // $state->{total_count} // 0 ;

	my $raw = $state->{matches} // [] ;
	my @matches ;
	for my $m (@$raw)
		{
		push @matches, { index => ($m->{index} // 0), text => ($m->{text} // '') } ;
		}

	_log("fetch_async: mc=$self->{_mc} tc=$self->{_tc} returned=" . scalar(@matches)) ;
	$cb->(\@matches, $self->{_mc}, $self->{_tc}) ;
	}) ;
}

# ------------------------------------------------------------------------------

sub cancel
{
my ($self) = @_ ;
_log("cancel: cancelling in-flight poller request") ;
$self->{process}->cancel() if $self->{process} ;
}

# ------------------------------------------------------------------------------

sub stop
{
my ($self) = @_ ;
_log("stop") ;
$self->{process}->stop() if $self->{process} ;
$self->{process} = undef ;
}

1 ;
