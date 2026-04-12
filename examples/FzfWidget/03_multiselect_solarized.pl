#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('03 - multi-select solarized-dark') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my @items = map { "file_$_.pm" } qw(alpha beta gamma delta epsilon zeta eta theta iota kappa) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme  => 'solarized-dark',
		multi  => 1,
		on_selection_change => sub
			{
			my ($w, $sel) = @_ ;
			printf STDERR "%d selected\n", scalar @$sel ;
			},
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
