package Gtk3::FzfWidget::SocketBackend ;

# FzfBackend implementation over fzf's HTTP API.
# Wraps Gtk3::FzfWidget::Process + StatePoller.

use strict ;
use warnings ;

our @ISA = ('Gtk3::FzfWidget::FzfBackend') ;
our $VERSION = '0.01' ;

my $_log_fh ;

sub _log
{
my ($msg) = @_ ;
return unless $ENV{FZFW_DEBUG} ;
require Time::HiRes ;
my ($s, $u) = Time::HiRes::gettimeofday() ;
my $line = sprintf "[%.3f] BACKEND:SOCKET: %s\n", $s + $u/1e6, $msg ;
print STDERR $line ;
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
	process   => $args{process},
	_mc       => 0,
	_tc       => 0,
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

my $prev_mc = $self->{_mc} ;
my $attempt = 0 ;
my $max     = 10 ;   # up to 10 × 50ms = 500ms total

# Send change-query synchronously so fzf processes it before the GET.
$self->{process}->post_sync("change-query($query)") ;

my $try ;
$try = sub
	{
	$attempt++ ;

	$self->{process}->get_state_async($limit, sub
		{
		my ($state) = @_ ;

		unless ($state)
			{
			_log("query_async: no state (attempt $attempt)") ;
			$cb->(undef, 0, 0) ;
			return ;
			}

		my $mc = $state->{matchCount} // $state->{match_count} // 0 ;
		my $tc = $state->{totalCount} // $state->{total_count} // 0 ;

		# Check if fzf has applied our query using the response's query field.
		my $resp_query = $state->{query} // '' ;
		if ($resp_query ne $query && $attempt < $max)
			{
			_log("query_async: fzf query='$resp_query' want='$query', retry $attempt/$max") ;
			Glib::Timeout->add(50, sub { $try->() ; return 0 }) ;
			return ;
			}

		$self->{_mc} = $mc ;
		$self->{_tc} = $tc ;

		my $raw     = $state->{matches} // [] ;
		my @matches = map { { index => ($_->{index} // 0), text => ($_->{text} // '') } } @$raw ;

		_log("query_async: mc=$mc tc=$tc returned=" . scalar(@matches) . " (attempt $attempt)") ;
		$cb->(\@matches, $mc, $tc) ;
		}) ;
	} ;

$try->() ;
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

	my $raw  = $state->{matches} // [] ;
	my @matches = map { { index => ($_->{index} // 0), text => ($_->{text} // '') } } @$raw ;

	_log("fetch_async: mc=$self->{_mc} tc=$self->{_tc} returned=" . scalar(@matches)) ;
	$cb->(\@matches, $self->{_mc}, $self->{_tc}) ;
	}) ;
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
