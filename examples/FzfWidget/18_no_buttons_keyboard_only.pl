#!/usr/bin/perl

# Example 18: keyboard-only interface, buttons and status hidden.
# Confirm with Return, cancel with Escape.
# Useful when embedding in a larger application.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "item $_" } 1 .. 20 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('18 - no buttons, keyboard only') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		show_buttons => 0,
		show_status  => 0,
		theme        => 'dark',
		on_confirm   => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel    => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
