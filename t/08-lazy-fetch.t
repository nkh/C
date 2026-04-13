#!/usr/bin/perl

# t/08-lazy-fetch.t
#
# Tests FzfBackend interface implementations (MockBackend) and the
# prefetch logic that FzfWidget uses.
#
# Uses MockBackend which delivers callbacks synchronously via Glib::Idle,
# but we pump the Glib main loop to process them in tests.

use strict ;
use warnings ;
use Test::More ;

# ---------------------------------------------------------------------------
# We need the Glib main loop to fire Glib::Idle callbacks from MockBackend.
# We pump it with a helper.

my $have_glib = eval { require Glib ; 1 } ;

unless ($have_glib)
	{
	plan skip_all => 'Glib required for backend tests' ;
	}

plan tests => 24 ;

require Gtk3::FzfWidget::FzfBackend ;

# Pump Glib main loop until $cond->() is true or 100 iterations pass.
sub pump_until
{
my ($cond) = @_ ;
for (1 .. 100)
	{
	Glib::MainContext->default->iteration(0) ;
	return 1 if $cond->() ;
	}
return 0 ;
}

# ---------------------------------------------------------------------------
# MockBackend basic tests

my @items = map { "item_$_" } 0 .. 199 ;
my $mock  = Gtk3::FzfWidget::MockBackend->new(items => \@items) ;

is $mock->total_count(), 200, 'MockBackend: total_count = 200' ;
is $mock->match_count(), 200, 'MockBackend: match_count = 200 (empty query)' ;

# ---------------------------------------------------------------------------
# query_async: empty query returns first N items

{
my ($got_matches, $got_mc, $got_tc) ;

$mock->query_async('', 50, sub
	{
	($got_matches, $got_mc, $got_tc) = @_ ;
	}) ;

pump_until(sub { defined $got_matches }) ;

ok defined $got_matches, 'query_async: callback fired' ;
is scalar @$got_matches, 50, 'query_async: 50 matches returned' ;
is $got_mc, 200, 'query_async: match_count = 200' ;
is $got_tc, 200, 'query_async: total_count = 200' ;
is $got_matches->[0]{index}, 0, 'query_async: first index = 0' ;
is $got_matches->[49]{index}, 49, 'query_async: last index = 49' ;
}

# ---------------------------------------------------------------------------
# query_async: non-empty query filters correctly

{
my $mock2 = Gtk3::FzfWidget::MockBackend->new(items => ['apple', 'apricot', 'banana', 'avocado']) ;
my ($got_matches, $got_mc) ;

$mock2->query_async('ap', 10, sub { ($got_matches, $got_mc) = @_ }) ;
pump_until(sub { defined $got_matches }) ;

is $got_mc, 2, 'query_async with filter: match_count = 2 (apple, apricot)' ;
is scalar @$got_matches, 2, 'query_async with filter: 2 results returned' ;

my @fruits = ("apple", "apricot", "banana", "avocado") ; my @texts = map { $fruits[$_->{index}] } @$got_matches ;
is_deeply [sort @texts], ['apple', 'apricot'], 'query_async: correct items matched' ;
}

# ---------------------------------------------------------------------------
# fetch_async: returns window for current query

{
my $mock3 = Gtk3::FzfWidget::MockBackend->new(items => \@items) ;
$mock3->query_async('', 50, sub {}) ;
pump_until(sub { $mock3->match_count() == 200 }) ;

my ($got_matches, $got_mc) ;
$mock3->fetch_async(100, sub { ($got_matches, $got_mc) = @_ }) ;
pump_until(sub { defined $got_matches }) ;

is scalar @$got_matches, 100, 'fetch_async: 100 matches returned' ;
is $got_matches->[99]{index}, 99, 'fetch_async: 100th index = 99' ;
is $got_mc, 200, 'fetch_async: match_count = 200' ;
}

# ---------------------------------------------------------------------------
# Prefetch simulation: mirrors FzfWidget _navigate + _prefetch_more logic

{
my $PREFETCH_BUFFER = 50 ;
my @all = map { "row_$_" } 0 .. 499 ;
my $mock4 = Gtk3::FzfWidget::MockBackend->new(items => \@all) ;

# Initial query: get first 100
my ($match_indices, $match_count) ;
$mock4->query_async('', 100, sub
	{
	my ($m, $mc) = @_ ;
	$match_indices = [map { $_->{index} } @$m] ;
	$match_count   = $mc ;
	}) ;
pump_until(sub { defined $match_indices }) ;

is scalar @$match_indices, 100, 'prefetch sim: initial 100 fetched' ;
is $match_count, 500, 'prefetch sim: match_count = 500' ;

my $prefetch_at = scalar(@$match_indices) - $PREFETCH_BUFFER ;
my $local_pos   = 0 ;

# Simulate navigating to prefetch_at
$local_pos = $prefetch_at ;

# Trigger prefetch because local_pos >= prefetch_at
my $fetch_done = 0 ;
$mock4->fetch_async(scalar(@$match_indices) + $PREFETCH_BUFFER, sub
	{
	my ($m, $mc) = @_ ;
	$match_indices = [map { $_->{index} } @$m] ;
	$match_count   = $mc ;
	$fetch_done    = 1 ;
	}) ;
pump_until(sub { $fetch_done }) ;

is scalar @$match_indices, 150, 'prefetch sim: extended to 150' ;
is $match_indices->[149], 149, 'prefetch sim: 150th index = 149' ;

# Navigate to the new prefetch_at
$prefetch_at = scalar(@$match_indices) - $PREFETCH_BUFFER ;
$local_pos   = $prefetch_at ;
$fetch_done  = 0 ;

$mock4->fetch_async(scalar(@$match_indices) + $PREFETCH_BUFFER, sub
	{
	my ($m, $mc) = @_ ;
	$match_indices = [map { $_->{index} } @$m] ;
	$fetch_done    = 1 ;
	}) ;
pump_until(sub { $fetch_done }) ;

is scalar @$match_indices, 200, 'prefetch sim: extended to 200' ;
}

# ---------------------------------------------------------------------------
# query change resets window

{
my @words = ('foo', 'foobar', 'bar', 'baz', 'fool') ;
my $mock5  = Gtk3::FzfWidget::MockBackend->new(items => \@words) ;

my ($m1, $mc1) ;
$mock5->query_async('foo', 10, sub { ($m1, $mc1) = @_ }) ;
pump_until(sub { defined $m1 }) ;

is $mc1, 3, 'query change: foo matches 3 (foo, foobar, fool)' ;

my ($m2, $mc2) ;
$mock5->query_async('bar', 10, sub { ($m2, $mc2) = @_ }) ;
pump_until(sub { defined $m2 }) ;

is $mc2, 2, 'query change: bar matches 2 (foobar, bar)' ;
isnt $mc1, $mc2, 'query change: different counts for different queries' ;
}

