use strict ;
use warnings ;
use Test::More ;

eval { require Test::Pod ; Test::Pod->import() } ;
plan skip_all => 'Test::Pod required for POD testing' if $@ ;

all_pod_files_ok() ;
