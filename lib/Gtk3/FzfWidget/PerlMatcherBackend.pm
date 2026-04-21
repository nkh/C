package Gtk3::FzfWidget::PerlMatcherBackend ;

# FzfBackend implementation using the pure-Perl PerlMatcher.
# No fzf process, no HTTP, no forks, no sockets.
# Callbacks delivered via Glib::Idle for consistent async contract.
#
# Use this when:
#   - fzf is not available
#   - Debugging the widget without fzf complexity
#   - Item counts are small enough that Perl matching is fast enough
#   - Testing query/filter logic in isolation

use strict ;
use warnings ;
use Glib ;
use Gtk3::FzfWidget::Matcher ;

our @ISA = ('Gtk3::FzfWidget::FzfBackend') ;
our $VERSION = '0.01' ;

my $_log_fh ;

sub _log
{
my ($msg) = @_ ;
return unless $ENV{FZFW_DEBUG} || $ENV{FZFW_LOG} ;
require Time::HiRes ;
my ($s, $u) = Time::HiRes::gettimeofday() ;
my $line = sprintf "[%.3f] PERLMATCHER: %s\n", $s + $u/1e6, $msg ;
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

my $matcher = Gtk3::FzfWidget::PerlMatcher->new() ;
my $items   = $args{items} // [] ;
$matcher->set_items($items) ;

return bless
	{
	matcher      => $matcher,
	_current_q   => '',
	_last_mc     => 0,
	}, $class ;
}

# ------------------------------------------------------------------------------

sub total_count { $_[0]->{matcher}->item_count() }
sub match_count { $_[0]->{_last_mc} }

# ------------------------------------------------------------------------------

sub query_async
{
my ($self, $query, $limit, $cb) = @_ ;

_log("query_async q='$query' limit=$limit items=" . $self->{matcher}->item_count()) ;

$self->{_current_q} = $query ;

my $matches = $self->{matcher}->match($query, $limit) ;
my $mc      = scalar @{$self->{matcher}->match($query, $self->{matcher}->item_count())} ;
my $tc      = $self->{matcher}->item_count() ;

$self->{_last_mc} = $mc ;

_log("query_async result: mc=$mc tc=$tc returned=" . scalar(@$matches)) ;

Glib::Idle->add(sub { $cb->($matches, $mc, $tc) ; return 0 }) ;
}

# ------------------------------------------------------------------------------

sub fetch_async
{
my ($self, $limit, $cb) = @_ ;

_log("fetch_async limit=$limit q='$self->{_current_q}'") ;

my $matches = $self->{matcher}->match($self->{_current_q}, $limit) ;
my $mc      = $self->{_last_mc} ;
my $tc      = $self->{matcher}->item_count() ;

Glib::Idle->add(sub { $cb->($matches, $mc, $tc) ; return 0 }) ;
}

# ------------------------------------------------------------------------------

sub cancel { }   # no-op — synchronous matching, nothing to cancel
sub stop   { }

1 ;
