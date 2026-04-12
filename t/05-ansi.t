use strict ;
use warnings ;
use Test::More ;

eval { require Gtk3 } ;
plan skip_all => 'Gtk3 required for ANSI tests' if $@ ;

plan tests => 9 ;

require Gtk3::FzfWidget ;

sub make_widget
{
return bless
	{
	colors =>
		{
		widget_fg => undef,
		match_fg  => '#f39c12',
		match_bg  => undef,
		cursor_fg => '#ffffff',
		cursor_bg => '#2d6db5',
		},
	highlight => 1,
	ansi      => 1,
	tab_width => 8,
	}, 'Gtk3::FzfWidget' ;
}

my $w = make_widget() ;

my $plain = $w->_ansi_to_markup('hello world') ;
is($plain, 'hello world', 'plain text unchanged') ;

my $amp = $w->_ansi_to_markup('a & b') ;
is($amp, 'a &amp; b', 'ampersand escaped') ;

my $red = $w->_ansi_to_markup("\e[31mred\e[0m") ;
like($red, qr/foreground="#cc0000"/, 'red foreground applied') ;
like($red, qr/>red<\/span>/, 'red text wrapped in span') ;

my $reset = $w->_ansi_to_markup("\e[31mred\e[0mnormal") ;
unlike($reset, qr/foreground.*normal/, 'text after reset has no color') ;

my $bold = $w->_ansi_to_markup("\e[1mbold\e[0m") ;
like($bold, qr/weight="bold"/, 'bold attribute applied') ;

my $bg = $w->_ansi_to_markup("\e[42mgreen bg\e[0m") ;
like($bg, qr/background="#4e9a06"/, 'green background applied') ;

my $combo = $w->_ansi_to_markup("\e[1;33myellow bold\e[0m") ;
like($combo, qr/foreground="#c4a000"/, 'yellow foreground in combined code') ;
like($combo, qr/weight="bold"/, 'bold in combined code') ;
