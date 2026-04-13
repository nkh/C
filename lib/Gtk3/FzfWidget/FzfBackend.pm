package Gtk3::FzfWidget::FzfBackend ;

# Abstract interface for fzf backends.
# Subclasses implement query_async and fetch_async.
#
# query_async($query, $limit, $cb)
#   Filter items by $query, return first $limit matching indices.
#   Calls $cb->(\@matches, $match_count, $total_count)
#   Each match: { index => N }
#   On error: $cb->(undef, 0, 0)
#
# fetch_async($limit, $cb)
#   Fetch first $limit matches for the CURRENT query (no query change).
#   Same callback contract.
#
# total_count()  — items known to backend so far (grows during load)
# match_count()  — matches for current query
# stop()         — release all resources

use strict ;
use warnings ;

our $VERSION = '0.01' ;

sub new         { die ref(shift) . "::new not implemented" }
sub query_async { die ref(shift) . "::query_async not implemented" }
sub fetch_async { die ref(shift) . "::fetch_async not implemented" }
sub total_count { 0 }
sub match_count { 0 }
sub stop        { }

1 ;

# ==============================================================================

package Gtk3::FzfWidget::MockBackend ;

# In-process backend — no forks, no sockets, no timers.
# Case-insensitive substring match.
# Callbacks delivered via Glib::Idle so callers are always async.

use strict ;
use warnings ;
use Glib ;

our @ISA = ('Gtk3::FzfWidget::FzfBackend') ;
our $VERSION = '0.01' ;

my $_log_fh ;

sub _log
{
my ($msg) = @_ ;
return unless $ENV{FZFW_DEBUG} ;
require Time::HiRes ;
my ($s, $u) = Time::HiRes::gettimeofday() ;
my $line = sprintf "[%.3f] BACKEND:MOCK: %s\n", $s + $u/1e6, $msg ;
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
	items       => $args{items} // [],
	_current_q  => '',
	_cache      => undef,   # arrayref of matching indices for _current_q
	}, $class ;
}

# ------------------------------------------------------------------------------

sub total_count { scalar @{$_[0]->{items}} }

sub match_count
{
my ($self) = @_ ;
$self->_rebuild_cache() unless defined $self->{_cache} ;
return scalar @{$self->{_cache}} ;
}

# ------------------------------------------------------------------------------

sub query_async
{
my ($self, $query, $limit, $cb) = @_ ;

$self->{_current_q} = $query ;
$self->{_cache}     = undef ;
$self->_rebuild_cache() ;

my $total = scalar @{$self->{items}} ;
my $mc    = scalar @{$self->{_cache}} ;
my $end   = ($limit > $mc ? $mc : $limit) - 1 ;
my @result = $end < 0
	? ()
	: map { { index => $_ } } @{$self->{_cache}}[0 .. $end] ;

_log("query_async q='$query' limit=$limit mc=$mc total=$total returning=" . scalar(@result)) ;

Glib::Idle->add(sub { $cb->(\@result, $mc, $total) ; return 0 }) ;
}

# ------------------------------------------------------------------------------

sub fetch_async
{
my ($self, $limit, $cb) = @_ ;

$self->_rebuild_cache() unless defined $self->{_cache} ;

my $total = scalar @{$self->{items}} ;
my $mc    = scalar @{$self->{_cache}} ;
my $end   = ($limit > $mc ? $mc : $limit) - 1 ;
my @result = $end < 0
	? ()
	: map { { index => $_ } } @{$self->{_cache}}[0 .. $end] ;

_log("fetch_async limit=$limit mc=$mc total=$total returning=" . scalar(@result)) ;

Glib::Idle->add(sub { $cb->(\@result, $mc, $total) ; return 0 }) ;
}

# ------------------------------------------------------------------------------

sub stop { _log("stop") }

# ------------------------------------------------------------------------------

sub _rebuild_cache
{
my ($self) = @_ ;

my $q     = lc($self->{_current_q}) ;
my $items = $self->{items} ;

if ($q eq '')
	{
	$self->{_cache} = [0 .. $#$items] ;
	}
else
	{
	my @hits ;
	for my $i (0 .. $#$items)
		{
		push @hits, $i if index(lc($items->[$i]), $q) >= 0 ;
		}
	$self->{_cache} = \@hits ;
	}

_log("_rebuild_cache q='$self->{_current_q}' hits=" . scalar(@{$self->{_cache}})) ;
}

1 ;
