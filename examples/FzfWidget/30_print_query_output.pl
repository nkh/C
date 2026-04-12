#!/usr/bin/perl

# Example 30 — Printing the query alongside the selection.
#
# Demonstrates:
#   - The on_confirm callback receives the query as its third argument
#   - Printing "query: <text>" before the selected items
#   - This is how fzfw --print-query works internally

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "item $_" } 1 .. 20 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('30 - print query') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme      => 'dark',
		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;

			# Print query first, then each selected item
			print "query\t$query\n" if length $query ;
			print "$_->[0]\n" for @$sel ;

			Gtk3->main_quit() ;
			},
		on_cancel  => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
