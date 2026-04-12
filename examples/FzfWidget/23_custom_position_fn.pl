#!/usr/bin/perl

# Example 23 — Custom position_fn to override fuzzy match highlighting.
#
# Demonstrates:
#   - position_fn config key: a coderef ($text, $query) -> \@indices
#     that returns which character positions in $text to highlight
#   - The default implementation finds the leftmost subsequence match.
#     This example uses a different strategy: highlights ALL occurrences
#     of the first query character, not just the leftmost sequence.
#   - This is useful for implementing word-boundary matching, prefix
#     matching, or any other highlighting strategy.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my @items = qw(
	application approachable append appeal apple applicable
	banana breadboard breach bridge broken browse
	cat catch category cattle clause close
	) ;

# Custom position function: highlight every occurrence of every query
# character anywhere in the text (not just as a subsequence).
my $highlight_all = sub
	{
	my ($text, $query) = @_ ;

	return [] unless length $query ;

	my $lc_text  = lc $text ;
	my %qchars   = map { $_ => 1 } split //, lc $query ;
	my @positions ;

	for my $i (0 .. length($lc_text) - 1)
		{
		my $ch = substr($lc_text, $i, 1) ;
		push @positions, $i if $qchars{$ch} ;
		}

	return \@positions ;
	} ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('23 - custom position_fn') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@items,
	config =>
		{
		theme       => 'dark',

		# Override the built-in fuzzy position finder with our custom one.
		# Remove this key to revert to the default subsequence matcher.
		position_fn => $highlight_all,

		on_confirm  => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel   => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
