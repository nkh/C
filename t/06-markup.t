use strict ;
use warnings ;
use Test::More ;

eval { require Gtk3 } ;
plan skip_all => 'Gtk3 required for markup tests' if $@ ;

plan tests => 12 ;

require Gtk3::FzfWidget ;

sub make_widget
{
my (%args) = @_ ;
return bless
	{
	colors =>
		{
		widget_fg => $args{widget_fg},
		match_fg  => $args{match_fg} // '#f39c12',
		match_bg  => undef,
		cursor_fg => '#ffffff',
		cursor_bg => '#2d6db5',
		},
	highlight => $args{highlight} // 1,
	ansi      => 0,
	tab_width => $args{tab_width} // 8,
	}, 'Gtk3::FzfWidget' ;
}

my $w = make_widget() ;

my $m = $w->_make_markup('hello', [], 0) ;
is($m, 'hello', 'no query, no widget_fg: plain text') ;

my $w2 = make_widget(widget_fg => '#ffffff') ;
my $m2 = $w2->_make_markup('hello', [], 0) ;
is($m2, '<span foreground="#ffffff">hello</span>', 'no query, widget_fg applied') ;

my $m3 = $w->_make_markup('hello', [0], 0) ;
like($m3, qr/<span foreground="#f39c12">h<\/span>/, 'position 0 highlighted') ;
like($m3, qr/ello/, 'remaining chars present') ;

my $m4 = $w->_make_markup('hello', [], 1) ;
like($m4, qr/^<span background="#2d6db5" foreground="#ffffff">/, 'cursor span wraps markup') ;

my $m5 = $w->_make_markup('a & b', [], 0) ;
like($m5, qr/a &amp; b/, 'ampersand escaped') ;

my $m6 = $w->_make_markup('a < b', [], 0) ;
like($m6, qr/a &lt; b/, 'less-than escaped') ;

my $w3 = make_widget(tab_width => 8) ;
my $expanded = $w3->_make_markup("a\tb", [], 0) ;
like($expanded, qr/a {7}b/, 'tab expanded to 7 spaces from col 1') ;

my $expanded2 = $w3->_make_markup("\tb", [], 0) ;
like($expanded2, qr/^ {8}b/, 'tab at col 0 expands to 8 spaces') ;

my $w4 = make_widget(tab_width => 4) ;
my $expanded3 = $w4->_make_markup("ab\tc", [], 0) ;
like($expanded3, qr/ab {2}c/, 'tab expands correctly with tab_width 4') ;

my $w5 = make_widget(highlight => 0) ;
my $m7 = $w5->_make_markup('hello', [0], 0) ;
is($m7, 'hello', 'highlight disabled: no span even with positions') ;

my $expanded4 = $w3->_make_markup("\thello", [1], 0) ;
like($expanded4, qr/foreground="#f39c12">h<\/span>/, 'position remapped after tab expansion') ;
