#!/usr/bin/perl

# Example 19: on_ready callback — fires when fzf finishes loading all items.
# Use get_total_count() and get_match_count() inside the callback.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "item $_" } 1 .. 50 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('19 - on_ready callback') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme    => 'dark',
		on_ready => sub
			{
			my ($w) = @_ ;
			printf STDERR "on_ready: %d items loaded, %d matching\n",
				$w->get_total_count(),
				$w->get_match_count() ;
			},
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
