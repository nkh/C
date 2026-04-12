#!/usr/bin/perl

# Example 08 — Pre-fill the query entry and pre-check items in multi mode.
#
# Demonstrates:
#   - initial_query: text placed in the search box before the user types
#   - initial_selection: list of original item indices to pre-select
#   - multi mode with visible checkboxes
#
# The widget navigates to each pre-selected row, toggles it, then resets
# to the top. The entry shows the initial query immediately on startup.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = qw(
	apple banana cherry date elderberry
	fig grape honeydew kiwi lemon
	mango nectarine orange papaya quince
	) ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('08 - initial query + selection') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme => 'dark',

		# Start with 'a' in the search box so only items matching 'a' show
		initial_query => 'a',

		# Multi mode so the user can toggle multiple items
		multi => 1,

		# Pre-select items at original indices 0 (apple), 2 (cherry), 4 (elderberry)
		# These get checked automatically on startup regardless of the current query
		initial_selection => [0, 2, 4],

		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "query: $query\n" ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel  => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
