package Gtk3::FzfWidget::Store ;

use strict ;
use warnings ;

# ListStore columns:
# col 0 = markup         (Glib::String)
# col 1 = original index (Glib::Int)
# col 2 = selected flag  (Glib::Boolean)
# col 3 = cell-bg color  (Glib::String)
# col 4 = cell-bg-set    (Glib::Boolean)
# col 5 = pixbuf         (Gtk3::Gdk::Pixbuf)
# col 6 = visible        (Glib::Boolean)  ← TreeModelFilter visibility column

# _row_iters is indexed by orig_idx (permanent, never reordered).
# _match_indices is the ordered list of orig_idx values currently visible.
# The TreeModelFilter shows only rows where col 6 = true.

# ------------------------------------------------------------------------------

sub new
{
my ($class) = @_ ;

my $list_store = Gtk3::ListStore->new(
	'Glib::String', 'Glib::Int',  'Glib::Boolean',
	'Glib::String', 'Glib::Boolean', 'Gtk3::Gdk::Pixbuf',
	'Glib::Boolean',
	) ;

my $filter = Gtk3::TreeModelFilter->new($list_store, undef) ;
$filter->set_visible_column(6) ;

return bless
	{
	list_store     => $list_store,
	filter         => $filter,
	_row_iters     => [],   # orig_idx → Gtk3::TreeIter in list_store
	_match_indices => [],   # ordered filter-row → orig_idx
	}, $class ;
}

# ------------------------------------------------------------------------------
# The filter model is what the TreeView receives.

sub model { $_[0]->{filter} }

# ------------------------------------------------------------------------------
# reset: hide all rows and clear match list.
# Does NOT remove rows from the store — they stay for reuse.

sub reset
{
my ($self) = @_ ;

# Hide every row that has been appended.
for my $iter (@{$self->{_row_iters}})
	{
	next unless $iter ;
	$self->{list_store}->set($iter, 6, 0) ;
	}

$self->{_match_indices} = [] ;
}

# ------------------------------------------------------------------------------
# append_row: add a new item to the store (first time only) and show it.
# If the item was already added in a previous query cycle, just show it.

sub append_row
{
my ($self, $row, $orig_idx, $markup, $cell_bg, $selected) = @_ ;

if (!$self->{_row_iters}[$orig_idx])
	{
	my $iter = $self->{list_store}->append() ;
	$self->{list_store}->set($iter,
		0, $markup,
		1, $orig_idx,
		2, ($selected ? 1 : 0),
		3, $cell_bg // '#000000',
		4, $cell_bg ? 1 : 0,
		6, 1,
		) ;
	$self->{_row_iters}[$orig_idx] = $iter ;
	}
else
	{
	my $iter = $self->{_row_iters}[$orig_idx] ;
	$self->{list_store}->set($iter,
		0, $markup,
		2, ($selected ? 1 : 0),
		3, $cell_bg // '#000000',
		4, $cell_bg ? 1 : 0,
		6, 1,
		) ;
	}
}

# ------------------------------------------------------------------------------

sub append_row_pixbuf
{
my ($self, $row, $orig_idx, $markup, $cell_bg, $selected, $pb) = @_ ;

$self->append_row($row, $orig_idx, $markup, $cell_bg, $selected) ;
$self->{list_store}->set($self->{_row_iters}[$orig_idx], 5, $pb) ;
}

# ------------------------------------------------------------------------------
# set_row: update markup/bg/selected for a row currently in the filter.
# $row is a filter-row number; orig_idx is looked up from _match_indices.

sub set_row
{
my ($self, $row, $markup, $cell_bg, $selected) = @_ ;

my $orig_idx = $self->{_match_indices}[$row] ;
return unless defined $orig_idx ;
my $iter = $self->{_row_iters}[$orig_idx] ;
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

my $orig_idx = $self->{_match_indices}[$row] ;
return unless defined $orig_idx ;
my $iter = $self->{_row_iters}[$orig_idx] ;
return unless $iter ;
$self->{list_store}->set($iter, 2, ($selected ? 1 : 0)) ;
}

# ------------------------------------------------------------------------------
# set_match_indices: make exactly these orig_idx values visible, in order.
# Hides all others that are currently visible.

sub set_match_indices
{
my ($self, $indices) = @_ ;

my %new = map { $_ => 1 } @$indices ;

# Hide rows that were visible but are no longer matching.
for my $old_idx (@{$self->{_match_indices}})
	{
	next if $new{$old_idx} ;
	my $iter = $self->{_row_iters}[$old_idx] ;
	$self->{list_store}->set($iter, 6, 0) if $iter ;
	}

# Show rows that are newly matching (may already be visible — that's fine).
for my $idx (@$indices)
	{
	my $iter = $self->{_row_iters}[$idx] ;
	$self->{list_store}->set($iter, 6, 1) if $iter ;
	}

$self->{_match_indices} = $indices ;
}

# ------------------------------------------------------------------------------

sub match_indices { $_[0]->{_match_indices} }
sub match_count   { scalar @{$_[0]->{_match_indices}} }
sub orig_idx      { $_[0]->{_match_indices}[$_[1]] }
sub iter          { $_[0]->{_row_iters}[$_[1]] }

# ------------------------------------------------------------------------------

1 ;
