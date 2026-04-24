package Gtk3::FzfWidget::SocketBackend ;

# FzfBackend implementation over fzf's HTTP API.
# Wraps Gtk3::FzfWidget::Process + StatePoller.

use strict ;
use warnings ;
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
	process => $args{process},
	_mc     => 0,
	_tc     => 0,
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

$self->{process}->post_sync("change-query($query)") ;

$self->{process}->get_state_async($limit, sub
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

	my $raw = $state->{matches} // [] ;
	my @matches ;
	for my $m (@$raw)
		{
		push @matches, { index => ($m->{index} // 0), text => ($m->{text} // '') } ;
		}

	_log("query_async RESULT: mc=$self->{_mc} tc=$self->{_tc} returned=" . scalar(@matches)) ;
	$cb->(\@matches, $self->{_mc}, $self->{_tc}) ;
	}) ;
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
