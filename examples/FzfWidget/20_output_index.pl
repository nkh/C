#!/usr/bin/perl

# Example 20: print the original item index instead of text.
# Useful when the calling script needs to reference items by position.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = qw(apple banana cherry date elderberry fig grape) ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('20 - output index') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme      => 'dark',
		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;
			# Print index, not text
			printf "index %d: %s\n", $_->[1], $_->[0] for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel  => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
