#!/usr/bin/perl

# Example 04 — Header label with the query entry placed below the list.
#
# Demonstrates:
#   - layout => [qw(header list query)] to reorder widget slots
#   - header_font_family and header_font_size to match the list font
#     (critical: the header must use the same font as the list items
#     or column alignment will be impossible)
#   - header and list both use Monospace at the same size

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = (
	'apple     fruit      red',
	'banana    fruit      yellow',
	'broccoli  vegetable  green',
	'carrot    vegetable  orange',
	'cherry    fruit      red',
	) ;

my $font   = 'Monospace' ;
my $fsize  = 13 ;

# The header must use exactly the same font family and size as the items,
# otherwise the column labels will not line up with the data below them.
my $header = "name       type       color" ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('04 - header + query below') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,

	# header slot appears first, then list, then query at the bottom
	layout => [qw(header list query)],

	config =>
		{
		theme              => 'dark',

		# List font — must match header font exactly for alignment
		font_family        => $font,
		font_size          => $fsize,

		# Header font — set to same values as list font
		header             => $header,
		header_font_family => $font,
		header_font_size   => $fsize,

		tab_width          => 4,

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
