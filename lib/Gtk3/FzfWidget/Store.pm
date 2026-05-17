package Gtk3::FzfWidget::Store ;

use strict ;
use warnings ;

# col 0 = markup, col 1 = original index, col 2 = selected flag,
# col 3 = cell-background string, col 4 = cell-background-set boolean,
# col 5 = pixbuf (optional)

# ------------------------------------------------------------------------------

sub new
{
my ($class) = @_ ;

my $list_store = Gtk3::ListStore->new(
	'Glib::String', 'Glib::Int', 'Glib::Boolean',
	'Glib::String', 'Glib::Boolean', 'Gtk3::Gdk::Pixbuf',
	) ;

return bless
	{
	list_store     => $list_store,
	_row_iters     => [],
	_match_indices => [],
	}, $class ;
}

# ------------------------------------------------------------------------------

sub model { $_[0]->{list_store} }

# ------------------------------------------------------------------------------

sub reset
{
my ($self) = @_ ;

$self->{_match_indices} = [] ;
$self->{_row_iters}     = [] ;
$self->{list_store}->clear() ;
}

# ------------------------------------------------------------------------------

sub append_row
{
my ($self, $row, $orig_idx, $markup, $cell_bg, $selected) = @_ ;

my $iter = $self->{list_store}->append() ;
$self->{list_store}->set($iter,
	0, $markup,
	1, $orig_idx,
	2, ($selected ? 1 : 0),
	3, $cell_bg // '#000000',
	4, $cell_bg ? 1 : 0,
	) ;
$self->{_row_iters}[$row] = $iter ;
}

# ------------------------------------------------------------------------------

sub append_row_pixbuf
{
my ($self, $row, $orig_idx, $markup, $cell_bg, $selected, $pb) = @_ ;

$self->append_row($row, $orig_idx, $markup, $cell_bg, $selected) ;
$self->{list_store}->set($self->{_row_iters}[$row], 5, $pb) ;
}

# ------------------------------------------------------------------------------

sub set_row
{
my ($self, $row, $markup, $cell_bg, $selected) = @_ ;

my $iter = $self->{_row_iters}[$row] ;
return unless $iter ;

$self->{list_store}->set($iter,
	0, $markup,
	2, ($selected ? 1 : 0),
	3, $cell_bg // '#000000',
	4, $cell_bg ? 1 : 0,
	) ;
}

# ------------------------------------------------------------------------------

sub set_selected
{
my ($self, $row, $selected) = @_ ;

my $iter = $self->{_row_iters}[$row] ;
return unless $iter ;
$self->{list_store}->set($iter, 2, ($selected ? 1 : 0)) ;
}

# ------------------------------------------------------------------------------

sub set_match_indices
{
my ($self, $indices) = @_ ;
$self->{_match_indices} = $indices ;
}

# ------------------------------------------------------------------------------

sub match_indices { $_[0]->{_match_indices} }
sub match_count   { scalar @{$_[0]->{_match_indices}} }
sub orig_idx      { $_[0]->{_match_indices}[$_[1]] }
sub iter          { $_[0]->{_row_iters}[$_[1]] }

# ------------------------------------------------------------------------------

1 ;
