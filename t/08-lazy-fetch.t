#!/usr/bin/perl

# t/08-lazy-fetch.t
#
# Tests lazy fetch / scroll logic using mock objects — no GTK, fzf, or HTTP.
#
# The LazyFetch class mirrors the async callback design of FzfWidget:
#   - refresh() fires get_state_async, callback calls _maybe_fetch_more_async
#   - _maybe_fetch_more_async fires get_more_async when near end
#   - _refresh_finish updates cached_matches and lazy_fetched
#
# MockProcess uses synchronous delivery (calls callbacks immediately) so
# tests remain simple and deterministic.

use strict ;
use warnings ;
use Test::More ;

# ---------------------------------------------------------------------------
# MockProcess — synchronous stub (calls callbacks inline for test simplicity)
# ---------------------------------------------------------------------------

package MockProcess ;

sub new
{
my ($class, %args) = @_ ;
return bless
	{
	items       => $args{items} // [],
	total       => $args{total} // 0,
	}, $class ;
}

sub get_state_async
{
my ($self, $limit, $cb) = @_ ;
my @all   = @{$self->{items}} ;
my $mc    = scalar @all ;
my $end   = $limit < $mc ? $limit - 1 : $mc - 1 ;
my @matches = map { { text => $all[$_], index => $_ } } 0 .. $end ;
$cb->({ matchCount => $mc, totalCount => $self->{total} || $mc, matches => \@matches }) ;
}

sub get_more_async
{
my ($self, $offset, $limit, $cb) = @_ ;
my @all = @{$self->{items}} ;
my $mc  = scalar @all ;
if ($offset >= $mc) { $cb->([]) ; return }
my $end = $offset + $limit - 1 ;
$end = $mc - 1 if $end >= $mc ;
$cb->([map { { text => $all[$_], index => $_ } } $offset .. $end]) ;
}

1 ;

# ---------------------------------------------------------------------------
# LazyFetch — mirrors FzfWidget async refresh logic
# ---------------------------------------------------------------------------

package LazyFetch ;

sub new
{
my ($class, %args) = @_ ;
return bless
	{
	process              => $args{process},
	lazy_fetch_initial   => $args{lazy_fetch_initial}   // 50,
	lazy_fetch_page      => $args{lazy_fetch_page}       // 50,
	lazy_fetch_threshold => $args{lazy_fetch_threshold}  // 20,
	lazy_fetched         => 0,
	lazy_total_mc        => 0,
	cached_matches       => [],
	local_pos            => 0,
	last_query           => undef,
	current_query        => '',
	}, $class ;
}

sub refresh
{
my ($self) = @_ ;

my $query         = $self->{current_query} ;
my $query_changed = ($self->{last_query} // "\x00") ne $query ;

my $limit = $query_changed ? $self->{lazy_fetch_initial} : 1 ;

$self->{process}->get_state_async($limit, sub
	{
	my ($state) = @_ ;
	return unless $state ;

	my $mc = $state->{matchCount} // 0 ;
	$self->{lazy_total_mc} = $mc ;

	if ($query_changed)
		{
		my $matches = $state->{matches} // [] ;
		$self->{lazy_fetched} = scalar @$matches ;
		$self->_finish($state) ;
		$self->{last_query} = $query ;
		}
	else
		{
		$state->{matches} = $self->{cached_matches} ;
		$self->_maybe_fetch_more_async($state) ;
		}
	}) ;
}

sub _maybe_fetch_more_async
{
my ($self, $state) = @_ ;

my $fetched   = $self->{lazy_fetched} ;
my $total_mc  = $self->{lazy_total_mc} ;
my $threshold = $self->{lazy_fetch_threshold} ;
my $page      = $self->{lazy_fetch_page} ;

if ($fetched >= $total_mc || $self->{local_pos} < $fetched - $threshold)
	{
	$self->_finish($state) ;
	return ;
	}

my $new_limit = $fetched + $page ;
$new_limit = $total_mc if $new_limit > $total_mc ;

$self->{process}->get_state_async($new_limit, sub
	{
	my ($fresh) = @_ ;
	return $self->_finish($state) unless $fresh ;

	my $new_matches = $fresh->{matches} // [] ;
	if (@$new_matches > $fetched)
		{
		$state->{matches}     = $new_matches ;
		$self->{lazy_fetched} = scalar @$new_matches ;
		}
	$self->_finish($state) ;
	}) ;
}

sub _finish
{
my ($self, $state) = @_ ;
$self->{cached_matches} = $state->{matches} // [] ;
}

sub navigate
{
my ($self, $delta) = @_ ;

my $matches = $self->{cached_matches} ;
my $count   = scalar @$matches ;
return unless $count ;

my $old_pos = $self->{local_pos} ;
my $new_pos = $old_pos + $delta ;

$new_pos = 0          if $new_pos < 0 ;
$new_pos = $count - 1 if $new_pos >= $count ;

if ($delta > 0
	&& $new_pos == $count - 1
	&& $self->{lazy_total_mc} > $self->{lazy_fetched})
	{
	# Async fetch — in test, MockProcess is synchronous so this resolves now
	$self->refresh() ;
	$matches = $self->{cached_matches} ;
	$count   = scalar @$matches ;
	my $desired = $old_pos + $delta ;
	$new_pos = $desired < $count ? $desired : $count - 1 ;
	}

return if $new_pos == $old_pos ;
$self->{local_pos} = $new_pos ;
}

1 ;

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

package main ;

my $TOTAL     = 200 ;
my @all_items = map { "item_$_" } 0 .. $TOTAL - 1 ;

# ---- Test 1: initial load --------------------------------------------------

{
my $proc = MockProcess->new(items => \@all_items, total => $TOTAL) ;
my $lf   = LazyFetch->new(process => $proc, lazy_fetch_initial => 50) ;

$lf->refresh() ;

is scalar @{$lf->{cached_matches}}, 50, 'initial load: 50 rows' ;
is $lf->{lazy_fetched},  50,   'initial load: lazy_fetched=50' ;
is $lf->{lazy_total_mc}, 200,  'initial load: lazy_total_mc=200' ;
}

# ---- Test 2: navigate to last row triggers fetch ---------------------------

{
my $proc = MockProcess->new(items => \@all_items, total => $TOTAL) ;
my $lf   = LazyFetch->new(
	process              => $proc,
	lazy_fetch_initial   => 50,
	lazy_fetch_page      => 50,
	lazy_fetch_threshold => 20,
	) ;

$lf->refresh() ;
is scalar @{$lf->{cached_matches}}, 50, 'before scroll: 50 rows' ;

$lf->{local_pos} = 48 ;
$lf->navigate(1) ;

is $lf->{local_pos}, 49, 'cursor at row 49' ;
is scalar @{$lf->{cached_matches}}, 100, 'after last row: 100 rows fetched' ;
is $lf->{lazy_fetched}, 100, 'lazy_fetched=100' ;
}

# ---- Test 3: two consecutive extensions ------------------------------------

{
my $proc = MockProcess->new(items => \@all_items, total => $TOTAL) ;
my $lf   = LazyFetch->new(
	process              => $proc,
	lazy_fetch_initial   => 50,
	lazy_fetch_page      => 50,
	lazy_fetch_threshold => 20,
	) ;

$lf->refresh() ;

$lf->{local_pos} = 48 ;
$lf->navigate(1) ;
is scalar @{$lf->{cached_matches}}, 100, 'first extension: 100 rows' ;

$lf->{local_pos} = 98 ;
$lf->navigate(1) ;
is scalar @{$lf->{cached_matches}}, 150, 'second extension: 150 rows' ;
is $lf->{lazy_fetched}, 150, 'lazy_fetched=150' ;
}

# ---- Test 4: no fetch when fully loaded ------------------------------------

{
my $small = [map { "item_$_" } 0 .. 29] ;
my $proc  = MockProcess->new(items => $small, total => 30) ;
my $lf    = LazyFetch->new(process => $proc, lazy_fetch_initial => 50) ;

$lf->refresh() ;
is scalar @{$lf->{cached_matches}}, 30, 'small: all 30 rows loaded' ;

$lf->{local_pos} = 28 ;
$lf->navigate(1) ;
is scalar @{$lf->{cached_matches}}, 30, 'small: no extra fetch' ;
is $lf->{local_pos}, 29, 'cursor at last row 29' ;
}

# ---- Test 5: query change resets window ------------------------------------

{
my $proc = MockProcess->new(items => \@all_items, total => $TOTAL) ;
my $lf   = LazyFetch->new(
	process              => $proc,
	lazy_fetch_initial   => 50,
	lazy_fetch_page      => 50,
	lazy_fetch_threshold => 20,
	) ;

$lf->refresh() ;
$lf->{local_pos} = 48 ;
$lf->navigate(1) ;
is scalar @{$lf->{cached_matches}}, 100, 'pre-change: 100 rows' ;

$lf->{current_query} = 'item_1' ;
$lf->refresh() ;

is $lf->{lazy_fetched}, 50,  'after query change: window reset to 50' ;
is scalar @{$lf->{cached_matches}}, 50, 'after query change: cached reset to 50' ;
}

# ---- Test 6: steady-state refresh preserves loaded rows -------------------

{
my $proc = MockProcess->new(items => \@all_items, total => $TOTAL) ;
my $lf   = LazyFetch->new(
	process              => $proc,
	lazy_fetch_initial   => 50,
	lazy_fetch_page      => 50,
	lazy_fetch_threshold => 20,
	) ;

$lf->refresh() ;
$lf->{local_pos} = 48 ;
$lf->navigate(1) ;
is scalar @{$lf->{cached_matches}}, 100, 'pre-steady: 100 rows' ;

# Steady-state refresh (same query, cursor not near end) must preserve rows
$lf->{local_pos} = 10 ;
$lf->refresh() ;
is scalar @{$lf->{cached_matches}}, 100,
	'steady-state refresh: 100 rows preserved (O(1) — no re-fetch)' ;
}

done_testing() ;
