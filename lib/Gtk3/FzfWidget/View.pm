package Gtk3::FzfWidget::View ;

use strict ;
use warnings ;

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;

my $model      = $args{model}      or die "View->new: model required" ;
my $name       = $args{name}       // 'fzfw-list' ;
my $multi      = $args{multi}      // 0 ;
my $image_fn   = $args{image_fn} ;
my $colors     = $args{colors}     // {} ;
my $font_family = $args{font_family} ;
my $font_size   = $args{font_size} ;
my $image_max_width  = $args{image_max_width}  // 64 ;
my $image_max_height = $args{image_max_height} // 64 ;

my $tv = Gtk3::TreeView->new_with_model($model) ;
$tv->set_name($name) ;
$tv->set_headers_visible(0) ;
$tv->set_enable_search(0) ;
$tv->get_selection()->set_mode('single') ;
$tv->set_fixed_height_mode(1) if $image_fn ;

# Checkbox column — always created, visible only in multi mode
my $toggle_col  = Gtk3::TreeViewColumn->new() ;
my $toggle_cell = Gtk3::CellRendererToggle->new() ;
$toggle_cell->set(activatable => 0) ;
$toggle_cell->set(cell_background => $colors->{checkbox_bg}) if $colors->{checkbox_bg} ;
$toggle_col->pack_start($toggle_cell, 0) ;
$toggle_col->add_attribute($toggle_cell, 'active', 2) ;
$toggle_col->set_sizing('fixed') if $image_fn ;
$toggle_col->set_visible($multi ? 1 : 0) ;
$tv->append_column($toggle_col) ;

# Pixbuf column — hidden until images confirmed
my $pixbuf_col  = Gtk3::TreeViewColumn->new() ;
my $pixbuf_cell = Gtk3::CellRendererPixbuf->new() ;
$pixbuf_cell->set('width'  => $image_max_width) ;
$pixbuf_cell->set('height' => $image_max_height) ;
$pixbuf_col->pack_start($pixbuf_cell, 0) ;
$pixbuf_col->add_attribute($pixbuf_cell, 'pixbuf', 5) ;
$pixbuf_col->set_visible(0) ;
$pixbuf_col->set_sizing('fixed') if $image_fn ;
$tv->append_column($pixbuf_col) ;

# Text column
my $text_col  = Gtk3::TreeViewColumn->new() ;
my $text_cell = Gtk3::CellRendererText->new() ;

if ($font_family || $font_size)
	{
	my $font_desc = '' ;
	$font_desc .= $font_family         if $font_family ;
	$font_desc .= ' ' . $font_size     if $font_size ;
	$text_cell->set('font' => $font_desc) ;
	}

$text_col->pack_start($text_cell, 1) ;
$text_col->add_attribute($text_cell, 'markup', 0) ;
$text_col->add_attribute($text_cell, 'cell-background', 3) ;
$text_col->add_attribute($text_cell, 'cell-background-set', 4) ;
$text_col->set_expand(1) ;
$text_col->set_sizing('fixed') if $image_fn ;
$tv->append_column($text_col) ;

my $scroll_win = Gtk3::ScrolledWindow->new(undef, undef) ;
$scroll_win->set_policy('never', 'automatic') ;
$scroll_win->add($tv) ;

return bless
	{
	tv          => $tv,
	scroll_win  => $scroll_win,
	toggle_col  => $toggle_col,
	pixbuf_col  => $pixbuf_col,
	}, $class ;
}

# ------------------------------------------------------------------------------
# The scroll_win is what gets packed into the layout.

sub widget { $_[0]->{scroll_win} }

# ------------------------------------------------------------------------------
# The TreeView itself, for signal connections in FzfWidget.

sub tv { $_[0]->{tv} }

# ------------------------------------------------------------------------------

sub get_name { $_[0]->{tv}->get_name() }

# ------------------------------------------------------------------------------

sub set_sensitive
{
my ($self, $val) = @_ ;
$_[0]->{scroll_win}->set_sensitive($val) ;
}

# ------------------------------------------------------------------------------

sub show_pixbuf_column { $_[0]->{pixbuf_col}->set_visible(1) }

# ------------------------------------------------------------------------------

sub set_toggle_visible
{
my ($self, $val) = @_ ;
$self->{toggle_col}->set_visible($val ? 1 : 0) ;
}

# ------------------------------------------------------------------------------

sub set_model
{
my ($self, $model) = @_ ;
$self->{tv}->set_model($model) ;
}

# ------------------------------------------------------------------------------

sub scroll_to_top
{
my ($self) = @_ ;
$self->{tv}->scroll_to_point(0, 0) ;
}

# ------------------------------------------------------------------------------

sub scroll_to_row
{
my ($self, $row, $align) = @_ ;
$align //= 0.5 ;
my $path = Gtk3::TreePath->new_from_string("$row") ;
$self->{tv}->scroll_to_cell($path, undef, 1, $align, 0.0) ;
}

# ------------------------------------------------------------------------------

sub visible_range
{
my ($self) = @_ ;
return $self->{tv}->get_visible_range() ;
}

# ------------------------------------------------------------------------------

1 ;
