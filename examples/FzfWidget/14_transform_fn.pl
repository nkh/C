#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('14 - transform_fn decorates display') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

opendir(my $dh, '.') or die $! ;
my @files = sort grep { !/^\.\.?$/ } readdir($dh) ;
closedir($dh) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@files,
	config =>
		{
		theme        => 'dark',
		font_family  => 'Monospace',
		transform_fn => sub
			{
			my ($text) = @_ ;
			return -d $text ? "[dir] $text"
			     : -x $text ? "[exe] $text"
			     : -l $text ? "[lnk] $text"
			     :             "      $text" ;
			},
		on_confirm => sub
			{
			# Confirm returns original text, not transformed text
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
