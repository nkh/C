use strict ;
use warnings ;
use Test::More tests => 6 ;

use Gtk3::FzfWidget::Client ;

# Test construction
my $client = Gtk3::FzfWidget::Client->new(port => 39999) ;
ok($client, 'Client->new returns object') ;
is($client->{port}, 39999, 'port stored correctly') ;
is($client->{host}, '127.0.0.1', 'default host is 127.0.0.1') ;
is($client->{sock_get}, undef, 'sock_get starts undef') ;

# Test custom host
my $client2 = Gtk3::FzfWidget::Client->new(host => '192.168.1.1', port => 32000) ;
is($client2->{host}, '192.168.1.1', 'custom host stored') ;

# Test connect failure returns 0 gracefully (nothing listening on 39999)
{
local *STDERR ;
open STDERR, '>', '/dev/null' ;
my $result = $client->_connect_get() ;
is($result, 0, '_connect_get returns 0 when nothing listening') ;
}
