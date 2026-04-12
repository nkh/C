#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('15 - custom keybindings') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my @items = map { "item $_" } 1 .. 30 ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme       => 'dark',
		multi       => 1,
		keybindings =>
			{
			confirm      => 'ctrl+return',
			cancel       => 'ctrl+c',
			clear_query  => 'ctrl+k',
			focus_entry  => 'ctrl+e',
			select_all   => 'ctrl+a',
			deselect_all => 'ctrl+d',
			},
		on_confirm  => sub
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
