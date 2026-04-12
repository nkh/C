#!/usr/bin/perl

# Example 27 — Using get_match_count and get_total_count.
#
# Demonstrates:
#   - Reading live match and total counts from outside the widget
#   - A Glib timer reads the counts every 500ms and prints them
#   - This pattern is useful when the calling app needs to react to
#     the number of visible items (e.g. disable a button when zero match)

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Glib ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "item $_" } 1 .. 50 ;
my $widget ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('27 - match counts') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

$widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme  => 'dark',
		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel  => sub { Gtk3->main_quit() },
		},
	) ;

# Poll counts from outside the widget every 500ms
Glib::Timeout->add(500, sub
	{
	return 0 unless defined $widget ;
	printf STDERR "match: %d / total: %d\n",
		$widget->get_match_count(),
		$widget->get_total_count() ;
	return 1 ;
	}) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
