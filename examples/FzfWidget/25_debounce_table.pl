#!/usr/bin/perl

# Example 25 — Custom debounce table for large item sets.
#
# Demonstrates:
#   - debounce_table: controls how long to wait after the last keystroke
#     before sending the query to fzf.
#   - Useful when the item list is large and sending every keystroke would
#     cause excessive HTTP traffic and visible lag.
#   - Each row is [total_item_threshold, debounce_ms].
#     The table is evaluated top to bottom; the first matching row wins.
#     undef threshold means "everything else".

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "item $_ — " . ('x' x int(rand(60))) } 1 .. 50_000 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('25 - debounce table (50k items)') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme => 'dark',

		# Custom debounce table tuned for large datasets.
		# Below 1000 items: react quickly (30ms).
		# 1000–20000 items: moderate delay (150ms).
		# 20000–100000 items: longer delay (300ms).
		# Anything larger: maximum delay (500ms).
		debounce_table =>
			[
			[   1_000,  30],
			[  20_000, 150],
			[ 100_000, 300],
			[   undef, 500],
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
