use strict ;
use warnings ;
use Test::More ;

eval { require Gtk3 } ;
plan skip_all => 'Gtk3 required for config tests' if $@ ;

eval { require IO::Pty } ;
plan skip_all => 'IO::Pty required for config tests' if $@ ;

plan tests => 12 ;

require Gtk3::FzfWidget ;

# Suppress _build_ui and _start_fzf for unit testing
no warnings 'redefine' ;
local *Gtk3::FzfWidget::_build_ui  = sub {} ;
local *Gtk3::FzfWidget::_start_fzf = sub {} ;

Gtk3->init() ;

# Invalid theme dies
my $err = '' ;
eval
	{
	Gtk3::FzfWidget->new(config => { theme => 'nonexistent' }) ;
	} ;
$err = $@ ;

ok($err, 'invalid theme produces error') ;
like($err, qr/Unknown theme/, 'error mentions Unknown theme') ;
like($err, qr/nonexistent/, 'error mentions bad theme name') ;

# Valid themes accepted
for my $theme (qw(normal dark solarized-dark solarized-light))
	{
	my $w = eval { Gtk3::FzfWidget->new(config => { theme => $theme }) } ;
	ok(!$@, "theme '$theme' accepted") ;
	}

# User color overrides theme
my $w = Gtk3::FzfWidget->new(
	config =>
		{
		theme  => 'dark',
		colors => { cursor_bg => '#deadbe' },
		},
	) ;
is($w->{colors}{cursor_bg}, '#deadbe', 'user color overrides theme') ;
isnt($w->{colors}{widget_bg}, undef, 'other theme colors still applied') ;

# Default values
my $d = Gtk3::FzfWidget->new() ;
is($d->{font_family},  'Monospace', 'default font_family') ;
is($d->{font_size},    15,          'default font_size') ;
is($d->{tab_width},    8,           'default tab_width') ;
