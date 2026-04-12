#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('02 - dark theme, custom cursor') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my @items = map { "item $_" } 1 .. 30 ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme  => 'dark',
		colors => { cursor_bg => '#8b0000', cursor_fg => '#ffffff' },
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
