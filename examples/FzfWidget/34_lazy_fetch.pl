#!/usr/bin/perl

# Example 34 — Large dataset with preemptive prefetch.
#
# Demonstrates:
#   - 500,000 items streamed to fzf via a coderef iterator (ItemWriter forks
#     a child writer so the GTK main loop is never blocked).
#
#   - prefetch_buffer: when the cursor is within this many rows of the end of
#     the fetched window, the next page is fetched in the background before
#     the display end is reached.  Default 100.
#
#   - All scrolling is local — no fzf HTTP calls on Up/Down/Tab.
#     fzf is only contacted when the query changes or a prefetch triggers.
#
#   - No timers run while the user is idle (stable query, cursor not near end).
#
# Debug: FZFW_DEBUG=1 FZFW_LOG=/tmp/fzfw.log perl 34_lazy_fetch.pl
# Run:   perl 34_lazy_fetch.pl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

# ---- Iterator coderef --------------------------------------------------------

my $TOTAL  = 500_000 ;
my $BATCH  = 1_000 ;
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

		# Fetch this many rows ahead of the cursor so data is ready
		# before the display end is reached.
		prefetch_buffer => 100,

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
