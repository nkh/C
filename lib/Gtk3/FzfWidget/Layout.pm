package Gtk3::FzfWidget::Layout ;

use strict ;
use warnings ;

sub new
{
my ($class, %args) = @_ ;

my $self = {
	slots   => $args{slots} // [qw(query list status)],
	widgets => {},
	} ;

return bless $self, $class ;
}

# ------------------------------------------------------------------------------

sub build
{
my ($self, $box, $widgets) = @_ ;

$self->{widgets} = $widgets ;

for my $slot (@{$self->{slots}})
	{
	my $w = $widgets->{$slot} ;
	next unless $w ;

	if ($slot eq 'list')
		{
		$box->pack_start($w, 1, 1, 0) ;
		}
	else
		{
		$box->pack_start($w, 0, 0, 0) ;
		}
	}
}

# ------------------------------------------------------------------------------

sub get_widget
{
my ($self, $slot) = @_ ;

return $self->{widgets}{$slot} ;
}

1 ;
