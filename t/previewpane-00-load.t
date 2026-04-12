use strict ;
use warnings ;
use Test::More ;

eval { require Gtk3 } ;
plan skip_all => 'Gtk3 required' if $@ ;

plan tests => 1 ;

use_ok('Gtk3::PreviewPane') ;
