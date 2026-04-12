#!/usr/bin/perl

# Example 32 — Ctrl+A to select all, Ctrl+D to deselect all.
#
# Demonstrates:
#   - Ctrl+A selects every visible match at once
#   - Ctrl+D clears all selections
#   - on_selection_change fires once per bulk operation with the full new set

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "file_$_.txt" } 'a' .. 'z' ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('32 - select all / deselect all') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		multi  => 1,
		theme  => 'dark',

		# on_selection_change fires after Ctrl+A or Ctrl+D as well as Tab
		on_selection_change => sub
			{
			my ($w, $sel, $changed_idx, $state, $text) = @_ ;
			printf STDERR "%d items selected\n", scalar @$sel ;
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
