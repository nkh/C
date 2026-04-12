#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('10 - custom status format + print query') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my @items = map { "item_$_" } 1 .. 100 ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		multi         => 1,
		theme         => 'dark',
		status_format => sub
			{
			my ($mc, $tc, $sc) = @_ ;
			return "$mc of $tc" . ($sc ? "  ($sc marked)" : '') ;
			},
		on_confirm    => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "query: $query\n" ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
