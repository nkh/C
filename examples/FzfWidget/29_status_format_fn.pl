#!/usr/bin/perl

# Example 29 — Custom status bar format with a coderef.
#
# Demonstrates:
#   - status_format as a coderef receiving ($match_count, $total_count, $selected_count)
#   - Custom string that changes meaning when multi-select is active
#   - No selected count shown when nothing is selected

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "file_$_.txt" } 'a' .. 'z' ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('29 - custom status format') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		multi  => 1,
		theme  => 'dark',

		# Custom status: "5 of 26" or "5 of 26  [3 marked]" when selections exist
		status_format => sub
			{
			my ($mc, $tc, $sc) = @_ ;
			my $base = "$mc of $tc" ;
			return $sc ? "$base  [$sc marked]" : $base ;
			},

		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel  => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
