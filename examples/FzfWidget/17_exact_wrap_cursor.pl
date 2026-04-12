#!/usr/bin/perl

# Example 17: exact search mode with wrap cursor.
# The list wraps at top and bottom.
# Search only matches exact substrings, not fuzzy.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "item $_" } 1 .. 20 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('17 - exact search + wrap cursor') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		search_mode => 'exact',
		wrap_cursor => 1,
		theme       => 'dark',
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
