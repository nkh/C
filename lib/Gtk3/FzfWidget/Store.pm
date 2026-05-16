package Gtk3::FzfWidget::Store ;

use strict ;
use warnings ;

# Store abstraction — all direct list_store / _row_iters / _match_indices
# access goes through these subs.  Phase 1: identical behaviour to current
# inline code.  Phase 2 (future): swap to TreeModelFilter + visibility column.

# ------------------------------------------------------------------------------

sub _store_reset
{
my ($self) = @_ ;

$self->{_match_indices} = [] ;
$self->{_row_iters}     = [] ;
$self->{list_store}->clear() ;
}

# ------------------------------------------------------------------------------

sub _store_append_row
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

sub _store_append_row_pixbuf
{
my ($self, $row, $orig_idx, $markup, $cell_bg, $selected, $pb) = @_ ;

$self->_store_append_row($row, $orig_idx, $markup, $cell_bg, $selected) ;
$self->{list_store}->set($self->{_row_iters}[$row], 5, $pb) ;
}

# ------------------------------------------------------------------------------

sub _store_set_row
{
my ($self, $row, $markup, $cell_bg, $selected) = @_ ;

my $iter = $self->{_row_iters}[$row] ;
return unless $iter ;

$self->{list_store}->set($iter,
	0, $markup,
	3, $cell_bg // '#000000',
	4, $cell_bg ? 1 : 0,
	) ;
$self->{list_store}->set($iter, 2, ($selected ? 1 : 0))
	if $self->{multi} ;
}

# ------------------------------------------------------------------------------

sub _store_set_selected
{
my ($self, $row, $selected) = @_ ;

my $iter = $self->{_row_iters}[$row] ;
return unless $iter ;
$self->{list_store}->set($iter, 2, ($selected ? 1 : 0)) ;
}

# ------------------------------------------------------------------------------

sub _store_set_match_indices
{
my ($self, $indices) = @_ ;
$self->{_match_indices} = $indices ;
}

# ------------------------------------------------------------------------------

1 ;
