use strict ;
use warnings ;
use Test::More ;

eval { require Test::Pod::Coverage ; Test::Pod::Coverage->import() } ;
plan skip_all => 'Test::Pod::Coverage required' if $@ ;

pod_coverage_ok('Gtk3::FzfWidget') ;
