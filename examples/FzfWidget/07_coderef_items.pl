#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('07 - coderef items (lazy loading)') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

# Items are computed on demand — useful for large or dynamic lists
my $items_fn = sub
	{
	my @result ;
	opendir(my $dh, '/usr/bin') or return [] ;
	while (my $f = readdir($dh))
		{
		next if $f =~ /^\./ ;
		push @result, $f ;
		}
	closedir($dh) ;
	return [sort @result] ;
	} ;

my $widget = Gtk3::FzfWidget->new(
	items  => $items_fn,
	config =>
		{
		theme      => 'dark',
		header     => '/usr/bin — select a command',
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
