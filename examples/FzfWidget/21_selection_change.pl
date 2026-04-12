#!/usr/bin/perl

# Example 21 — on_selection_change callback with full change details.
#
# Demonstrates:
#   - New callback signature: ($widget, $selections, $changed_idx, $state, $text)
#     $selections  — arrayref of all currently selected [$text, $index] pairs
#     $changed_idx — original index of the item just toggled
#     $state       — 1 if the item was just selected, 0 if deselected
#     $text        — text of the item that changed
#   - Selection can be toggled by pressing Tab or clicking any row

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = map { "file_$_.txt" } 'a' .. 'z' ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('21 - selection change with details') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		multi  => 1,
		theme  => 'dark',

		# Callback receives the full selection set plus details about
		# the single item that triggered this call
		on_selection_change => sub
			{
			my ($w, $sel, $changed_idx, $state, $text) = @_ ;
			my $action = $state ? 'selected' : 'deselected' ;
			printf STDERR "%s: %s (index %d) — %d total selected\n",
				$action, $text, $changed_idx, scalar @$sel ;
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
