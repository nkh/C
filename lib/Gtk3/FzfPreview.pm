package Gtk3::FzfPreview ;

use strict ;
use warnings ;
use utf8 ;
use Gtk3 ;
use Glib::Object::Subclass 'Gtk3::Box' ;
use Gtk3::FzfWidget ;
use Gtk3::PreviewPane ;
use File::Basename qw(basename) ;
use List::Util qw(sum max) ;

our $VERSION = '0.01' ;

my %DEFAULTS =
	(
	fzf_width       => undef,    # undef = auto-compute from item lengths
	resizable       => 0,
	show_fzf        => 1,
	show_preview    => 1,
	hide_fzf_key    => 'ctrl+p',
	hide_preview_key => 'ctrl+o',
	) ;

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;

my $config = $args{config} // {} ;

my $self = Glib::Object::new($class) ;
$self->set_orientation('horizontal') ;
$self->set_spacing(0) ;

$self->{items}            = $args{items}            // [] ;
$self->{item_to_file}     = $args{item_to_file}     // undef ;
$self->{fzf_width}        = $config->{fzf_width}    // $DEFAULTS{fzf_width} ;
$self->{resizable}        = $config->{resizable}    // $DEFAULTS{resizable} ;
$self->{show_fzf}         = $config->{show_fzf}     // $DEFAULTS{show_fzf} ;
$self->{show_preview}     = $config->{show_preview} // $DEFAULTS{show_preview} ;
$self->{hide_fzf_key}     = $config->{hide_fzf_key}     // $DEFAULTS{hide_fzf_key} ;
$self->{hide_preview_key} = $config->{hide_preview_key} // $DEFAULTS{hide_preview_key} ;
$self->{on_confirm}       = $config->{on_confirm} ;
$self->{on_cancel}        = $config->{on_cancel} ;
$self->{on_preview}       = $config->{on_preview} ;
$self->{fzf_config}       = $config->{fzf}     // {} ;
$self->{preview_config}   = $config->{preview} // {} ;

$self->_build_ui() ;

return $self ;
}

# ------------------------------------------------------------------------------

sub _resolve_file
{
my ($self, $text, $index) = @_ ;

# Priority: hashref lookup, then coderef, then direct file test
if (ref $self->{item_to_file} eq 'HASH')
	{
	return $self->{item_to_file}{$text} ;
	}
elsif (ref $self->{item_to_file} eq 'CODE')
	{
	return $self->{item_to_file}->($text, $index) ;
	}
elsif (-f $text || -d $text)
	{
	return $text ;
	}

return undef ;
}

# ------------------------------------------------------------------------------

sub _compute_fzf_fraction
{
my ($self) = @_ ;

# If user specified an explicit fraction, use it
return $self->{fzf_width} if defined $self->{fzf_width} ;

# Auto-compute: if average item length > 40 chars, use 50/50
# otherwise give preview more space
my $items = $self->{items} ;

return 0.5 unless @$items ;

my $items_ref = ref $items eq 'CODE' ? $items->() : $items ;
my $avg_len   = @$items_ref
	? (sum(map { length($_) } @$items_ref) / scalar @$items_ref)
	: 20 ;

return $avg_len > 40 ? 0.5 : 0.3 ;
}

# ------------------------------------------------------------------------------

sub _build_ui
{
my ($self) = @_ ;

my $fzf_on_sel    = $self->{fzf_config}{on_selection_change} ;
my $fzf_on_ready  = $self->{fzf_config}{on_ready} ;
my $fzf_on_cursor = $self->{fzf_config}{on_cursor_change} ;

my %fzf_cfg = (
	%{$self->{fzf_config}},
	on_cursor_change => sub
		{
		my ($w, $text, $index) = @_ ;
		$self->preview_item($text, $index) ;
		$fzf_on_cursor->($w, $text, $index) if $fzf_on_cursor ;
		},
	on_selection_change => sub
		{
		my ($w, $sel, $changed_idx, $state, $text) = @_ ;
		$fzf_on_sel->($w, $sel, $changed_idx, $state, $text) if $fzf_on_sel ;
		},
	on_ready => sub
		{
		my ($w) = @_ ;
		# Preview the first item immediately on startup
		my $sel = $w->get_selection() ;
		$self->preview_item($sel->[0][0], $sel->[0][1]) if $sel && @$sel ;
		$fzf_on_ready->($w) if $fzf_on_ready ;
		},
	on_confirm => sub
		{
		my ($w, $sel, $query) = @_ ;
		$self->{on_confirm}->($self, $sel, $query) if $self->{on_confirm} ;
		},
	on_cancel => sub
		{
		$self->{on_cancel}->($self) if $self->{on_cancel} ;
		},
	) ;

$self->{fzf_widget} = Gtk3::FzfWidget->new(
	items  => $self->{items},
	config => \%fzf_cfg,
	) ;

# PreviewPane
$self->{preview_pane} = Gtk3::PreviewPane->new(
	config => $self->{preview_config},
	) ;

# Compute initial size fraction for the fzf pane
my $frac = $self->_compute_fzf_fraction() ;

if ($self->{resizable})
	{
	# Use a HPaned with a drag handle
	$self->{paned} = Gtk3::HPaned->new() ;
	$self->{paned}->pack1($self->{fzf_widget},   1, 0) ;
	$self->{paned}->pack2($self->{preview_pane}, 1, 0) ;
	$self->{paned}->set_vexpand(1) ;

	# Set initial divider position after realize so we know the allocated width.
	# get_allocation() may return a plain hashref on some GTK3 Perl versions,
	# so access width as a method with fallback to hash dereference.
	$self->signal_connect(realize => sub
		{
		my $alloc = $self->get_allocation() ;
		my $w     = ref $alloc eq 'HASH' ? $alloc->{width} : $alloc->width() ;
		$self->{paned}->set_position(int($w * $frac)) ;
		}) ;

	$self->pack_start($self->{paned}, 1, 1, 0) ;
	}
else
	{
	# Fixed fraction: both panes expand vertically; fzf width set via size_request.
	$self->{fzf_widget}->set_vexpand(1) ;
	$self->{preview_pane}->set_vexpand(1) ;

	$self->pack_start($self->{fzf_widget},   1, 1, 0) ;
	$self->pack_start($self->{preview_pane}, 1, 1, 0) ;

	# Apply fzf widget width after realize.
	$self->signal_connect(realize => sub
		{
		my $alloc = $self->get_allocation() ;
		my $w     = ref $alloc eq 'HASH' ? $alloc->{width} : $alloc->width() ;
		$self->{fzf_widget}->set_size_request(int($w * $frac), -1) ;
		}) ;
	}

# Keyboard shortcuts to hide/show each pane
$self->{fzf_widget}->signal_connect(realize => sub
	{
	my $win = $self->{fzf_widget}->get_toplevel() ;
	return unless $win && $win->isa('Gtk3::Window') ;
	$win->signal_connect('key-press-event', sub
		{
		$self->_on_global_key($_[1]) ;
		}) ;
	}) ;
}

# ------------------------------------------------------------------------------

sub _on_global_key
{
my ($self, $event) = @_ ;

my $keyval = $event->keyval() ;
my $state  = ${$event->get_state()} ;
my $ctrl   = ($state & 4) ? 1 : 0 ;

# Parse hide_fzf_key and hide_preview_key
my $hfk = _parse_key_spec($self->{hide_fzf_key}) ;
my $hpk = _parse_key_spec($self->{hide_preview_key}) ;

if ($hfk && $keyval == $hfk->{keyval} && ($ctrl ? 1 : 0) == $hfk->{ctrl})
	{
	if ($self->{fzf_widget}->get_visible())
		{
		$self->{fzf_widget}->hide() ;
		$self->{preview_pane}->set_hexpand(1) ;
		}
	else
		{
		$self->{fzf_widget}->show() ;
		}
	return 1 ;
	}

if ($hpk && $keyval == $hpk->{keyval} && ($ctrl ? 1 : 0) == $hpk->{ctrl})
	{
	if ($self->{preview_pane}->get_visible())
		{
		$self->{preview_pane}->hide() ;
		$self->{fzf_widget}->set_hexpand(1) ;
		}
	else
		{
		$self->{preview_pane}->show() ;
		}
	return 1 ;
	}

return 0 ;
}

# ------------------------------------------------------------------------------

sub _parse_key_spec
{
my ($spec) = @_ ;

return undef unless defined $spec ;

$spec    = lc $spec ;
my $ctrl = ($spec =~ s/ctrl\+//) ;

my %named =
	(
	'return'   => Gtk3::Gdk::KEY_Return,
	'escape'   => Gtk3::Gdk::KEY_Escape,
	'space'    => Gtk3::Gdk::KEY_space,
	'tab'      => Gtk3::Gdk::KEY_Tab,
	) ;

my $keyval = $named{$spec} ;
$keyval  //= Gtk3::Gdk::unicode_to_keyval(ord($spec)) if length($spec) == 1 ;

return undef unless defined $keyval ;

return { keyval => $keyval, ctrl => $ctrl ? 1 : 0 } ;
}

# ------------------------------------------------------------------------------

sub preview_item
{
my ($self, $text, $index) = @_ ;

my $path = $self->_resolve_file($text, $index) ;
return unless defined $path ;

my $extra = undef ;

# If user provided an on_preview callback, call it to get extra text
if ($self->{on_preview})
	{
	my ($cb_path, $cb_extra) = $self->{on_preview}->($self, $path, $text, $index) ;
	$path  = $cb_path  if defined $cb_path ;
	$extra = $cb_extra if defined $cb_extra ;
	}

$self->{preview_pane}->load($path, $extra) ;
}

sub _preview_item { $_[0]->preview_item($_[1], $_[2]) }

# ------------------------------------------------------------------------------

sub fzf_widget   { $_[0]->{fzf_widget} }
sub preview_pane { $_[0]->{preview_pane} }

1 ;

__END__

=head1 NAME

Gtk3::FzfPreview - Composite fuzzy-search and file preview widget

=head1 DOCUMENTATION

Full documentation is in L<Gtk3::FzfPreview> (F<lib/Gtk3/FzfPreview.pod>).

=cut
