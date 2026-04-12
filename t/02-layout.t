use strict ;
use warnings ;
use Test::More tests => 6 ;

use Gtk3::FzfWidget::Layout ;

# Test construction with defaults
my $layout = Gtk3::FzfWidget::Layout->new() ;
ok($layout, 'Layout->new returns object') ;
is_deeply($layout->{slots}, [qw(query list status)], 'default slots') ;

# Test construction with custom slots
my $layout2 = Gtk3::FzfWidget::Layout->new(slots => [qw(list query)]) ;
is_deeply($layout2->{slots}, [qw(list query)], 'custom slots stored') ;

# Test get_widget before build returns undef
is($layout->get_widget('query'), undef, 'get_widget before build returns undef') ;

# Test that build skips missing widget keys gracefully
# (uses a mock box that records pack_start calls)
{
package MockBox ;
sub new { bless { calls => [] }, shift }
sub pack_start { push @{$_[0]{calls}}, $_[1] }
}

my $box    = MockBox->new() ;
my $entry  = bless {}, 'MockWidget' ;
my $list   = bless {}, 'MockWidget' ;

$layout->build($box, { query => $entry, list => $list }) ;

is(scalar @{$box->{calls}}, 2, 'build packs only present widgets') ;
is($layout->get_widget('query'), $entry, 'get_widget returns correct widget') ;
