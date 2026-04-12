#!/usr/bin/perl

# Example 31 — Cursor wrap and page navigation.
#
# Demonstrates:
#   - wrap_cursor: cursor jumps from last item back to first and vice versa
#   - Page Down / Page Up move 10 rows at a time
#   - Ctrl+Home / Ctrl+End jump to the very first / last item

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { sprintf("row %03d", $_) } 1 .. 100 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('31 - wrap cursor + page navigation') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme       => 'dark',

		# When at the last item, pressing Down goes back to the first.
		# When at the first item, pressing Up goes to the last.
		wrap_cursor => 1,

		# Page Down / Page Up step size in rows.
		# undef = visible rows - 1 (default), so Page Down lands the last
		# visible row at the top. A fixed integer overrides this.
		page_step   => undef,

		on_confirm  => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel   => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
