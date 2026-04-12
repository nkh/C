#!/usr/bin/perl

# Example 24 — Click to toggle in multi mode.
#
# Demonstrates:
#   - Single click on any part of a row (checkbox, text, or empty space)
#     toggles the item's selection state in multi mode
#   - Tab key also toggles and moves down, as usual
#   - on_selection_change shows which item changed and the new state

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "option_$_" } 'a' .. 'p' ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('24 - click to toggle') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		multi  => 1,
		theme  => 'dark',
		on_selection_change => sub
			{
			my ($w, $sel, $changed_idx, $state, $text) = @_ ;
			printf STDERR "%s '%s' (now %d selected)\n",
				($state ? 'selected' : 'deselected'),
				$text,
				scalar @$sel ;
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
