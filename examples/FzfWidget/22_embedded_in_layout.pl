#!/usr/bin/perl

# Example 22: embedding FzfWidget inside a larger GTK layout.
# The widget is a Gtk3::Box subclass — pack it anywhere.
# Here: sidebar picker on the left, output label on the right.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = qw(
	Perl Python Ruby Go Rust JavaScript TypeScript
	Haskell OCaml Elixir Erlang Clojure Scala Java
	) ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('22 - embedded widget') ;
$win->set_default_size(700, 400) ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $main_box   = Gtk3::Box->new('horizontal', 0) ;
my $output_lbl = Gtk3::Label->new('Select a language') ;
$output_lbl->set_xalign(0.5) ;

my $picker = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		width        => 250,
		border_width => 0,
		theme        => 'dark',
		show_buttons => 0,
		persistent   => 1,
		on_confirm   => sub
			{
			my ($w, $sel, $query) = @_ ;
			$output_lbl->set_text("Selected: $_->[0]") for @$sel ;
			},
		on_cancel    => sub { Gtk3->main_quit() },
		},
	) ;

$main_box->pack_start($picker,     0, 0, 0) ;
$main_box->pack_start($output_lbl, 1, 1, 8) ;

$win->add($main_box) ;
$win->show_all() ;
Gtk3->main() ;
