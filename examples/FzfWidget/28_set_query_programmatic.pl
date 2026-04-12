#!/usr/bin/perl

# Example 28 — Setting the query programmatically.
#
# Demonstrates:
#   - set_query($text) public method changes the search from outside
#   - A series of Glib timers cycle through preset queries automatically
#   - Useful for building search UIs driven by external events

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Glib ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = qw(
	perl python ruby javascript typescript
	haskell ocaml elixir erlang clojure
	go rust java c cpp zig
	) ;

my $widget ;
my @queries   = ('p', 'py', 'r', 're', '') ;
my $query_idx = 0 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('28 - programmatic set_query') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

$widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme  => 'dark',
		on_ready => sub
			{
			# Once fzf is ready, cycle through queries every 1.5 seconds
			Glib::Timeout->add(1500, sub
				{
				return 0 unless defined $widget ;
				$widget->set_query($queries[$query_idx % scalar @queries]) ;
				$query_idx++ ;
				return 1 ;
				}) ;
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
