#!/usr/bin/perl

# Example 16 — Freeze and unfreeze during a bulk item reload.
#
# Demonstrates:
#   - freeze: suspends background polling and query processing
#   - set_query + set_items: replace the current list and query atomically
#   - unfreeze: resumes polling so the new list is displayed immediately
#
# Without freeze/unfreeze, a background poll arriving between set_query and
# set_items could briefly show stale state. Wrapping both calls in
# freeze/unfreeze guarantees the transition is invisible to the user.
#
# The reload button is outside the widget to show that freeze/unfreeze can
# be driven by any external control.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('16 - freeze/unfreeze during bulk update') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my @items_a = map { "set_A item $_" } 1 .. 20 ;
my @items_b = map { "set_B item $_" } 1 .. 20 ;

my $widget ;

# A button outside the widget triggers a bulk reload
my $reload_btn = Gtk3::Button->new('Reload with set B') ;
$reload_btn->signal_connect(clicked => sub
	{
	$widget->freeze() ;
	$widget->set_query('') ;
	$widget->set_items(\@items_b) ;
	$widget->unfreeze() ;
	}) ;

my $vbox = Gtk3::Box->new('vertical', 4) ;

$widget = Gtk3::FzfWidget->new(
	items  => \@items_a,
	config =>
		{
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

$vbox->pack_start($widget,     1, 1, 0) ;
$vbox->pack_start($reload_btn, 0, 0, 4) ;

$win->add($vbox) ;
$win->show_all() ;
Gtk3->main() ;
