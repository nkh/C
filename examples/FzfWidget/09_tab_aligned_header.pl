#!/usr/bin/perl

# Example 09 — Tab-aligned columns with a matching header.
#
# Demonstrates:
#   - Computing maximum field width per column for correct alignment
#   - Using spaces (not tabs) for alignment, since tabs render differently
#     across font sizes and tab_width settings
#   - header_font_family and header_font_size must match the list font exactly
#
# Technique: split each item on the delimiter, measure all fields column by
# column, find the maximum width in each column, then pad every field to that
# width with spaces. The header is padded the same way.

use strict ;
use warnings ;
use lib '../lib' ;
use List::Util qw(max) ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

# Raw data: [user, home, shell]
my @data = (
	['root',    '/root',              '/bin/bash'],
	['nobody',  '/nonexistent',       '/usr/sbin/nologin'],
	['daemon',  '/usr/sbin',          '/usr/sbin/nologin'],
	['www-data','/var/www',           '/usr/sbin/nologin'],
	['nkh',     '/home/nkh',          '/bin/zsh'],
	['postgres','/var/lib/postgresql','/bin/bash'],
	) ;

# Compute maximum width for each column
my @col_widths = (0, 0, 0) ;

for my $row (@data)
	{
	for my $i (0 .. 2)
		{
		$col_widths[$i] = max($col_widths[$i], length($row->[$i])) ;
		}
	}

# Also measure the header labels themselves
my @headers = ('user', 'home directory', 'shell') ;

for my $i (0 .. 2)
	{
	$col_widths[$i] = max($col_widths[$i], length($headers[$i])) ;
	}

# Build padded items — last column needs no padding
my @items = map
	{
	sprintf("%-*s  %-*s  %s",
		$col_widths[0], $_->[0],
		$col_widths[1], $_->[1],
		$_->[2])
	} @data ;

# Build padded header with the same widths
my $header = sprintf("%-*s  %-*s  %s",
	$col_widths[0], $headers[0],
	$col_widths[1], $headers[1],
	$headers[2]) ;

my $font  = 'Monospace' ;
my $fsize = 13 ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('09 - tab-aligned header') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	layout => [qw(header list query)],
	config =>
		{
		theme              => 'dark',
		font_family        => $font,
		font_size          => $fsize,
		header             => $header,
		header_font_family => $font,
		header_font_size   => $fsize,
		on_confirm         => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel          => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
