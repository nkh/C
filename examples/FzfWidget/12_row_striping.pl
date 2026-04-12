#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('12 - row striping with three colors') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my @items = map { "row $_ — some content here" } 1 .. 40 ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme        => 'dark',
		row_striping => ['#1e1e2e', '#2a1a2e', '#1a2e1e'],
		on_confirm   => sub
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
