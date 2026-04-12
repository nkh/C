#!/usr/bin/perl

# Example 33 — Reloading items while the widget is open.
#
# Demonstrates:
#   - reload_items(\@new_items) replaces the list without recreating the widget
#   - The current query is preserved across the reload
#   - A Glib timer simulates an external event that refreshes the list

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Glib ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @base_items = map { "item $_" } 1 .. 10 ;
my $widget ;
my $generation = 0 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('33 - reload_items') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

$widget = Gtk3::FzfWidget->new(
	items  => \@base_items,
	config =>
		{
		theme    => 'dark',
		on_ready => sub
			{
			# After fzf is ready, reload with a new list every 3 seconds
			Glib::Timeout->add(3000, sub
				{
				return 0 unless defined $widget ;
				$generation++ ;
				my @new_items = map { "gen${generation}_item_$_" } 1 .. (10 + $generation * 2) ;
				printf STDERR "reloading: %d items (generation %d)\n",
					scalar @new_items, $generation ;
				$widget->reload_items(\@new_items) ;
				return 1 ;
				}) ;
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
