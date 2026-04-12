use strict ;
use warnings ;
use Test::More ;

eval { require IO::Pty } ;
plan skip_all => 'IO::Pty required for Process tests' if $@ ;

plan tests => 7 ;

require Gtk3::FzfWidget::Process ;

ok( Gtk3::FzfWidget::Process::_version_lt('0.60.0', '0.65.0'), '0.60.0 < 0.65.0') ;
ok( Gtk3::FzfWidget::Process::_version_lt('0.64.9', '0.65.0'), '0.64.9 < 0.65.0') ;
ok(!Gtk3::FzfWidget::Process::_version_lt('0.65.0', '0.65.0'), '0.65.0 not < 0.65.0') ;
ok(!Gtk3::FzfWidget::Process::_version_lt('1.0.0',  '0.65.0'), '1.0.0 not < 0.65.0') ;
ok(!Gtk3::FzfWidget::Process::_version_lt('0.65.1', '0.65.0'), '0.65.1 not < 0.65.0') ;

my $proc = Gtk3::FzfWidget::Process->new(
	items  => ['a', 'b', 'c'],
	config => { multi => 1, start_delay_ms => 200 },
	) ;

ok($proc, 'Process->new returns object') ;
ok(defined $proc->{port}, 'port assigned (OS free port)') ;
