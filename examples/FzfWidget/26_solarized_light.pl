#!/usr/bin/perl

# Example 26 — Solarized light theme.
#
# Demonstrates:
#   - solarized-light theme with warm background
#   - Overriding one color key (border_color) while keeping the rest of the theme
#   - Match highlight color (orange) chosen to be legible on both the light
#     background and the blue cursor row

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "item $_" } 1 .. 20 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('26 - solarized light') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme  => 'solarized-light',

		# Override the border color to make the window edge more visible
		# on light desktop backgrounds
		colors => { border_color => '#93a1a1' },

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
