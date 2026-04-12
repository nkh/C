package Gtk3::PreviewPane ;

use strict ;
use warnings ;
use utf8 ;
use Encode qw(decode_utf8 is_utf8) ;
use Gtk3 ;
use Glib::Object::Subclass 'Gtk3::Box' ;
use File::Basename qw(basename) ;
use POSIX qw(floor) ;

our $VERSION = '0.01' ;

my $HAS_SOURCEVIEW = eval { require Gtk3::SourceView ; Gtk3::SourceView->import() ; 1 } ? 1 : 0 ;

# Map themes to GtkSourceView style scheme names
my %SV_SCHEME =
	(
	dark    => 'oblivion',
	light   => 'classic',
	normal  => 'classic',
	) ;

my %IMAGE_EXTS = map { $_ => 1 } qw(
	png jpg jpeg gif bmp webp tiff tif svg ico
	) ;

my %TEXT_EXTS = map { $_ => 1 } qw(
	pl pm py rb sh bash zsh js ts c h cpp rs go java
	txt md rst log conf ini yaml yml toml json xml html css
	) ;

# Default zoom steps — each step multiplies by this factor
my $DEFAULT_ZOOM_FACTOR = 1.3 ;

# Default vim-like keybindings for text mode
my %DEFAULT_VIM_KEYBINDINGS =
	(
	scroll_down    => 'j',
	scroll_up      => 'k',
	page_down      => 'ctrl+d',
	page_up        => 'ctrl+u',
	goto_top       => 'g',
	goto_bottom    => 'shift+g',
	) ;

my %DEFAULTS =
	(
	zoom_factor      => $DEFAULT_ZOOM_FACTOR,
	extra_position   => 'top',
	keybindings      => \%DEFAULT_VIM_KEYBINDINGS,
	fit_mode         => 'height',
	show_status      => 1,
	theme            => 'dark',
	font_family      => 'Monospace',
	font_size        => 13,
	use_source_view  => 1,
	) ;

my %THEMES =
	(
	dark =>
		{
		bg     => '#1e1e1e',
		fg     => '#ffffff',
		status_bg => '#252526',
		status_fg => '#aaaaaa',
		extra_bg  => '#252526',
		extra_fg  => '#cccccc',
		},
	light =>
		{
		bg     => '#ffffff',
		fg     => '#000000',
		status_bg => '#f0f0f0',
		status_fg => '#555555',
		extra_bg  => '#f0f0f0',
		extra_fg  => '#333333',
		},
	normal =>
		{
		bg     => undef,
		fg     => undef,
		status_bg => undef,
		status_fg => undef,
		extra_bg  => undef,
		extra_fg  => undef,
		},
	) ;

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;

my $config = $args{config} // {} ;

my $self = Glib::Object::new($class) ;
$self->set_orientation('vertical') ;
$self->set_spacing(0) ;

$self->{zoom_factor}      = $config->{zoom_factor}      // $DEFAULTS{zoom_factor} ;
$self->{extra_position}   = $config->{extra_position}   // $DEFAULTS{extra_position} ;
$self->{fit_mode}         = $config->{fit_mode}         // $DEFAULTS{fit_mode} ;
$self->{show_status}      = $config->{show_status}      // $DEFAULTS{show_status} ;
$self->{font_family}      = $config->{font_family}      // $DEFAULTS{font_family} ;
$self->{font_size}        = $config->{font_size}        // $DEFAULTS{font_size} ;
$self->{use_source_view}  = $config->{use_source_view}  // $DEFAULTS{use_source_view} ;

my $theme_name = $config->{theme} // $DEFAULTS{theme} ;
$self->{theme_name}   = $theme_name ;
$self->{theme_colors} = $THEMES{$theme_name} // $THEMES{dark} ;

# Merge user keybindings over defaults
my $ukb = $config->{keybindings} // {} ;
$self->{keybindings} =
	{
	%{$DEFAULTS{keybindings}},
	%$ukb,
	} ;

$self->{current_path}  = undef ;
$self->{current_mode}  = undef ;   # 'text', 'image', or undef
$self->{zoom_level}    = 1.0 ;
$self->{pixbuf_orig}   = undef ;
$self->{pixbuf_scaled} = undef ;
$self->{extra_text}    = undef ;

$self->_build_ui() ;

return $self ;
}

# ------------------------------------------------------------------------------

sub _build_ui
{
my ($self) = @_ ;

my $c = $self->{theme_colors} ;

# Extra label — shown above or below content when extra text is set
$self->{extra_label} = Gtk3::Label->new('') ;
$self->{extra_label}->set_xalign(0) ;
$self->{extra_label}->set_line_wrap(1) ;
$self->{extra_label}->set_no_show_all(1) ;

if ($c->{extra_bg} || $c->{extra_fg})
	{
	my @css_p ;
	push @css_p, "background-color: $c->{extra_bg}" if $c->{extra_bg} ;
	push @css_p, "color: $c->{extra_fg}"            if $c->{extra_fg} ;
	my $provider = Gtk3::CssProvider->new() ;
	$provider->load_from_data('label { ' . join(' ; ', @css_p) . ' }') ;
	$self->{extra_label}->get_style_context()->add_provider(
		$provider, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION) ;
	}

# Text view — use Gtk3::SourceView for syntax highlighting if available
if ($HAS_SOURCEVIEW && $self->{use_source_view})
	{
	$self->{text_buffer} = Gtk3::SourceView::Buffer->new() ;
	$self->{text_buffer}->set_highlight_syntax(1) ;
	$self->{text_buffer}->set_highlight_matching_brackets(0) ;

	my $scheme_name = $SV_SCHEME{ $self->{theme_name} } // 'classic' ;
	my $sm = Gtk3::SourceView::StyleSchemeManager->get_default() ;
	my $scheme = $sm->get_scheme($scheme_name) ;
	$self->{text_buffer}->set_style_scheme($scheme) if $scheme ;

	$self->{text_view} = Gtk3::SourceView::View->new_with_buffer($self->{text_buffer}) ;
	$self->{text_view}->set_show_line_numbers(0) ;
	$self->{text_view}->set_highlight_current_line(0) ;
	}
else
	{
	$self->{text_buffer} = Gtk3::TextBuffer->new() ;
	$self->{text_view}   = Gtk3::TextView->new_with_buffer($self->{text_buffer}) ;
	}

$self->{text_view}->set_editable(0) ;
$self->{text_view}->set_cursor_visible(0) ;
$self->{text_view}->set_wrap_mode('none') ;

if ($c->{bg} || $c->{fg} || $self->{font_family} || $self->{font_size})
	{
	my @css_p ;
	push @css_p, "background-color: $c->{bg}" if $c->{bg} ;
	push @css_p, "color: $c->{fg}"            if $c->{fg} ;
	push @css_p, "font-family: $self->{font_family}" if $self->{font_family} ;
	push @css_p, "font-size: $self->{font_size}pt"   if $self->{font_size} ;
	my $provider = Gtk3::CssProvider->new() ;
	$provider->load_from_data('textview { ' . join(' ; ', @css_p) . ' }') ;
	$self->{text_view}->get_style_context()->add_provider(
		$provider, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION) ;
	}

$self->{text_scroll} = Gtk3::ScrolledWindow->new(undef, undef) ;
$self->{text_scroll}->set_policy('automatic', 'automatic') ;
$self->{text_scroll}->add($self->{text_view}) ;

# Image view (GtkDrawingArea)
$self->{drawing_area} = Gtk3::DrawingArea->new() ;
$self->{drawing_area}->signal_connect(
	draw => sub { $self->_on_draw($_[1]) ; return 0 },
	) ;
$self->{drawing_area}->signal_connect(
	'size-allocate',
	sub { $self->_on_resize() },
	) ;

$self->{image_scroll} = Gtk3::ScrolledWindow->new(undef, undef) ;
$self->{image_scroll}->set_policy('automatic', 'automatic') ;
$self->{image_scroll}->add($self->{drawing_area}) ;

# Stack to switch between text and image modes
$self->{stack} = Gtk3::Stack->new() ;
$self->{stack}->add_named($self->{text_scroll},  'text') ;
$self->{stack}->add_named($self->{image_scroll}, 'image') ;

# Status bar
$self->{status_label} = Gtk3::Label->new('') ;
$self->{status_label}->set_xalign(0) ;
$self->{status_label}->set_no_show_all(!$self->{show_status}) ;

if ($c->{status_bg} || $c->{status_fg})
	{
	my @css_p ;
	push @css_p, "background-color: $c->{status_bg}" if $c->{status_bg} ;
	push @css_p, "color: $c->{status_fg}"            if $c->{status_fg} ;
	my $provider = Gtk3::CssProvider->new() ;
	$provider->load_from_data('label { ' . join(' ; ', @css_p) . ' }') ;
	$self->{status_label}->get_style_context()->add_provider(
		$provider, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION) ;
	}

# Pack: extra top (optional), content, extra bottom (optional), status
$self->pack_start($self->{extra_label}, 0, 0, 0)
	if $self->{extra_position} eq 'top' ;

$self->pack_start($self->{stack},        1, 1, 0) ;

$self->pack_start($self->{extra_label},  0, 0, 0)
	if $self->{extra_position} eq 'bottom' ;

$self->pack_start($self->{status_label}, 0, 0, 0)
	if $self->{show_status} ;

# Keyboard navigation
$self->{stack}->add_events(['key-press-mask']) ;
$self->{stack}->set_can_focus(1) ;
$self->{stack}->signal_connect(
	'key-press-event',
	sub { $self->_on_key_press($_[1]) },
	) ;
}

# ------------------------------------------------------------------------------

sub load
{
my ($self, $path, $extra) = @_ ;

$self->{current_path} = $path ;
$self->{extra_text}   = $extra ;

if (defined $extra)
	{
	my $text = $extra ;
	$text = decode_utf8($text) unless is_utf8($text) ;
	$self->{extra_label}->set_text($text) ;
	$self->{extra_label}->show() ;
	}
else
	{
	$self->{extra_label}->set_text('') ;
	$self->{extra_label}->hide() ;
	}

return unless defined $path && -r $path ;

my ($ext) = lc($path) =~ /\.([^.\/]+)$/ ;
$ext //= '' ;

if ($IMAGE_EXTS{$ext})
	{
	$self->_load_image($path) ;
	}
else
	{
	$self->_load_text($path) ;
	}
}

# ------------------------------------------------------------------------------

sub _load_text
{
my ($self, $path) = @_ ;

$self->{current_mode} = 'text' ;
$self->{stack}->set_visible_child_name('text') ;

# Set syntax language if using SourceView
if ($HAS_SOURCEVIEW && $self->{use_source_view})
	{
	my $lm   = Gtk3::SourceView::LanguageManager->get_default() ;
	my $lang = $lm->guess_language($path, undef) ;
	$self->{text_buffer}->set_language($lang) ;  # undef clears highlighting
	}

local $/ = undef ;
open my $fh, '<:encoding(UTF-8)', $path or do
	{
	$self->{text_buffer}->set_text("Cannot read: $path") ;
	$self->_update_status("$path (unreadable)") ;
	return ;
	} ;

my $content = <$fh> // '' ;
close $fh ;

$self->{text_buffer}->set_text($content) ;

# Scroll to top
my $start = $self->{text_buffer}->get_start_iter() ;
$self->{text_view}->scroll_to_iter($start, 0.0, 0, 0.0, 0.0) ;

my $lines = () = $content =~ /\n/g ;
$self->_update_status(sprintf("%s  —  %d lines", basename($path), $lines + 1)) ;
}

# ------------------------------------------------------------------------------

sub _load_image
{
my ($self, $path) = @_ ;

$self->{current_mode}  = 'image' ;
$self->{pixbuf_orig}   = undef ;
$self->{pixbuf_scaled} = undef ;
$self->{zoom_level}    = 1.0 ;
$self->{stack}->set_visible_child_name('image') ;

my $pb = eval { Gtk3::Gdk::Pixbuf->new_from_file($path) } ;

unless ($pb)
	{
	$self->_update_status("$path (cannot load image)") ;
	return ;
	}

$self->{pixbuf_orig} = $pb ;
$self->_apply_fit() ;
$self->_update_image_status() ;
}

# ------------------------------------------------------------------------------

sub _apply_fit
{
my ($self) = @_ ;

my $pb = $self->{pixbuf_orig} or return ;

my $alloc = $self->{image_scroll}->get_allocation() ;
my $aw    = ref $alloc eq 'HASH' ? $alloc->{width}  : $alloc->width() ;
my $ah    = ref $alloc eq 'HASH' ? $alloc->{height} : $alloc->height() ;

return unless $aw > 1 && $ah > 1 ;

my $orig_w = $pb->get_width() ;
my $orig_h = $pb->get_height() ;

my $scale ;

if ($self->{fit_mode} eq 'height')
	{
	$scale = $ah / $orig_h ;
	}
elsif ($self->{fit_mode} eq 'width')
	{
	$scale = $aw / $orig_w ;
	}
elsif ($self->{fit_mode} eq 'both')
	{
	# Scale to fit within the pane in both dimensions, preserving aspect ratio
	my $scale_h = $ah / $orig_h ;
	my $scale_w = $aw / $orig_w ;
	$scale = $scale_h < $scale_w ? $scale_h : $scale_w ;
	}
else
	{
	$scale = $self->{zoom_level} ;
	}

$self->{zoom_level} = $scale ;
$self->_rescale() ;
}

# ------------------------------------------------------------------------------

sub _rescale
{
my ($self) = @_ ;

my $pb = $self->{pixbuf_orig} or return ;

my $w = int($pb->get_width()  * $self->{zoom_level}) ;
my $h = int($pb->get_height() * $self->{zoom_level}) ;

$w = 1 if $w < 1 ;
$h = 1 if $h < 1 ;

$self->{pixbuf_scaled} = $pb->scale_simple($w, $h, 'bilinear') ;
$self->{drawing_area}->set_size_request($w, $h) ;
$self->{drawing_area}->queue_draw() ;
$self->_update_image_status() ;
}

# ------------------------------------------------------------------------------

sub _on_draw
{
my ($self, $cr) = @_ ;

my $pb = $self->{pixbuf_scaled} or return ;

Gtk3::Gdk::cairo_set_source_pixbuf($cr, $pb, 0, 0) ;
$cr->paint() ;
}

# ------------------------------------------------------------------------------

sub _on_resize
{
my ($self) = @_ ;

return unless defined $self->{current_mode}
	&& $self->{current_mode} eq 'image'
	&& $self->{fit_mode} ne 'none' ;

$self->_apply_fit() ;
}

# ------------------------------------------------------------------------------

sub _on_key_press
{
my ($self, $event) = @_ ;

my $keyval = $event->keyval() ;
my $state  = ${$event->get_state()} ;
my $ctrl   = ($state & 4) ? 1 : 0 ;
my $shift  = ($state & 1) ? 1 : 0 ;

if ($self->{current_mode} eq 'image')
	{
	# Zoom in
	if ($keyval == Gtk3::Gdk::KEY_plus || $keyval == Gtk3::Gdk::KEY_equal)
		{
		$self->{zoom_level} *= $self->{zoom_factor} ;
		$self->{fit_mode}    = 'none' ;
		$self->_rescale() ;
		return 1 ;
		}

	# Zoom out
	if ($keyval == Gtk3::Gdk::KEY_minus)
		{
		$self->{zoom_level} /= $self->{zoom_factor} ;
		$self->{zoom_level}  = 0.01 if $self->{zoom_level} < 0.01 ;
		$self->{fit_mode}    = 'none' ;
		$self->_rescale() ;
		return 1 ;
		}

	# Reset zoom to 100%
	if ($keyval == Gtk3::Gdk::KEY_0)
		{
		$self->{zoom_level} = 1.0 ;
		$self->{fit_mode}   = 'none' ;
		$self->_rescale() ;
		return 1 ;
		}

	# Fit to height
	if ($keyval == Gtk3::Gdk::KEY_f)
		{
		$self->{fit_mode} = 'height' ;
		$self->_apply_fit() ;
		return 1 ;
		}
	}

if ($self->{current_mode} eq 'text')
	{
	my $vadj = $self->{text_scroll}->get_vadjustment() ;

	# j — scroll down one line
	if ($keyval == Gtk3::Gdk::KEY_j)
		{
		$vadj->set_value($vadj->get_value() + $vadj->get_step_increment()) ;
		return 1 ;
		}

	# k — scroll up one line
	if ($keyval == Gtk3::Gdk::KEY_k)
		{
		$vadj->set_value($vadj->get_value() - $vadj->get_step_increment()) ;
		return 1 ;
		}

	# Ctrl+d — half page down
	if ($ctrl && $keyval == Gtk3::Gdk::KEY_d)
		{
		$vadj->set_value($vadj->get_value() + $vadj->get_page_size() / 2) ;
		return 1 ;
		}

	# Ctrl+u — half page up
	if ($ctrl && $keyval == Gtk3::Gdk::KEY_u)
		{
		$vadj->set_value($vadj->get_value() - $vadj->get_page_size() / 2) ;
		return 1 ;
		}

	# g — go to top
	if ($keyval == Gtk3::Gdk::KEY_g && !$shift)
		{
		$vadj->set_value($vadj->get_lower()) ;
		return 1 ;
		}

	# G — go to bottom
	if ($keyval == Gtk3::Gdk::KEY_G || ($shift && $keyval == Gtk3::Gdk::KEY_g))
		{
		$vadj->set_value($vadj->get_upper() - $vadj->get_page_size()) ;
		return 1 ;
		}
	}

return 0 ;
}

# ------------------------------------------------------------------------------

sub _update_status
{
my ($self, $text) = @_ ;

$self->{status_label}->set_text($text // '') ;
}

# ------------------------------------------------------------------------------

sub _update_image_status
{
my ($self) = @_ ;

return unless $self->{pixbuf_orig} ;

my $pb   = $self->{pixbuf_orig} ;
my $zoom = int($self->{zoom_level} * 100 + 0.5) ;

$self->_update_status(sprintf("%s  —  %dx%d  —  %d%%",
	basename($self->{current_path}),
	$pb->get_width(),
	$pb->get_height(),
	$zoom)) ;
}

# ------------------------------------------------------------------------------

sub set_extra_text
{
my ($self, $text) = @_ ;

$self->{extra_text} = $text ;

if (defined $text)
	{
	my $t = $text ;
	$t = decode_utf8($t) unless is_utf8($t) ;
	$self->{extra_label}->set_text($t) ;
	$self->{extra_label}->show() ;
	}
else
	{
	$self->{extra_label}->set_text('') ;
	$self->{extra_label}->hide() ;
	}
}

# ------------------------------------------------------------------------------

sub clear_extra_text { $_[0]->set_extra_text(undef) }

sub get_current_path { $_[0]->{current_path} }
sub get_current_mode { $_[0]->{current_mode} }
sub get_zoom_level   { $_[0]->{zoom_level} }

# ------------------------------------------------------------------------------

sub load_text_string
{
my ($self, $text) = @_ ;

$text //= '' ;
$text = decode_utf8($text) if !is_utf8($text) ;

$self->{current_mode} = 'text' ;
$self->{current_path} = undef ;
$self->{stack}->set_visible_child_name('text') ;

if ($HAS_SOURCEVIEW && $self->{use_source_view})
	{
	# Clear language — raw string has no filename to guess from
	$self->{text_buffer}->set_language(undef) ;
	}

$self->{text_buffer}->set_text($text) ;

my $start = $self->{text_buffer}->get_start_iter() ;
$self->{text_view}->scroll_to_iter($start, 0.0, 0, 0.0, 0.0) ;

my $lines = () = $text =~ /\n/g ;
$self->_update_status(sprintf("%d lines", $lines + 1)) ;
}

1 ;

__END__

=head1 NAME

Gtk3::PreviewPane - GTK3 widget for previewing text files and images

=head1 DOCUMENTATION

Full documentation is in L<Gtk3::PreviewPane> (F<lib/Gtk3/PreviewPane.pod>).

=cut
