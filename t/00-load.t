use strict ;
use warnings ;
use Test::More tests => 4 ;

use_ok('Gtk3::FzfWidget::Messages') ;
use_ok('Gtk3::FzfWidget::Layout') ;
use_ok('Gtk3::FzfWidget::Client') ;

SKIP:
	{
	eval { require IO::Pty } ;
	skip 'IO::Pty required', 1 if $@ ;
	use_ok('Gtk3::FzfWidget::Process') ;
	}
