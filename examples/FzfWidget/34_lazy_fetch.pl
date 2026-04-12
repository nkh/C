#!/usr/bin/perl

# Example 34 — Async item loading with lazy windowed result fetching.
#
# Demonstrates:
#   - Items provided as a coderef iterator: called repeatedly, each call
#     returns an arrayref of items, or undef when exhausted.
#     The ItemWriter module forks a child to stream items to fzf without
#     blocking the GTK main loop.  The widget appears and is interactive
#     immediately — fzf starts returning matches before all items are loaded.
#
#   - lazy_fetch_initial: rows fetched on first display after a query change.
#     Default 50 — small enough for near-instant first display.
#
#   - lazy_fetch_page: additional rows fetched each time the cursor approaches
#     the end of what is loaded.  Default 50.
#
#   - lazy_fetch_threshold: rows before the loaded window end that trigger the
#     next fetch.  Default 10.
#
#   - poll_ms: how often the widget polls fzf for updates.  Default 100ms.
#     A 20ms fast-poll fires for the first 500ms after startup and after each
#     query change so initial results appear quickly.
#
# Run: perl 34_lazy_fetch.pl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

# ---- Iterator coderef --------------------------------------------------------
# The coderef is called repeatedly by ItemWriter in the writer child.
# Each call returns an arrayref of items (up to BATCH items), or undef
# when there are no more items.  This avoids building the full array in memory.

my $TOTAL = 500_000 ;
my $BATCH = 1_000 ;
my $cursor = 0 ;

my $item_iter = sub
	{
	return undef if $cursor >= $TOTAL ;

	my $end   = $cursor + $BATCH ;
	$end      = $TOTAL if $end > $TOTAL ;

	my @batch = map
		{
		sprintf('entry %06d — %s', $_, join(' ', map { ('a'..'z')[rand 26] } 1 .. 8))
		}
		$cursor + 1 .. $end ;

	$cursor = $end ;

	return \@batch ;
	} ;

# ---- Widget ------------------------------------------------------------------

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title("34 - lazy load ($TOTAL items, iterator coderef)") ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => $item_iter,
	config =>
		{
		theme => 'dark',

		# First 50 rows shown immediately; more loaded on scroll.
		# Increase if you want more rows visible before first scroll.
		lazy_fetch_initial   => 50,

		# Rows fetched each time the cursor nears the end of loaded data.
		lazy_fetch_page      => 100,

		# Fetch more when cursor is within this many rows of the end.
		lazy_fetch_threshold => 20,

		# Poll interval after the 500ms fast-startup window.
		poll_ms              => 100,

		# Debounce typing: longer delay avoids hammering fzf while
		# it is still indexing 500k items.
		debounce_table =>
			[
			[ 100_000, 300 ],
			[   undef, 500 ],
			],

		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
