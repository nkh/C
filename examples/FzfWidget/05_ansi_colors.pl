#!/usr/bin/perl

use strict ;
use warnings ;
use utf8 ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('05 - ANSI colored input') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my @items = (
	"\e[32mgreen  — success\e[0m",
	"\e[31mred    — error\e[0m",
	"\e[33myellow — warning\e[0m",
	"\e[34mblue   — info\e[0m",
	"\e[35mviolet — debug\e[0m",
	"\e[36mcyan   — trace\e[0m",
	"\e[1mbold   — important\e[0m",
	"\e[1;33mbold yellow — critical\e[0m",
	) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		ansi       => 1,
		theme      => 'dark',
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
