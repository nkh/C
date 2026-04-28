package Gtk3::FzfWidget ;

use strict ;
use warnings ;
use utf8 ;
use Encode qw(decode_utf8 is_utf8) ;
use Gtk3 ;
use Glib::Object::Subclass 'Gtk3::Box' ;
use Gtk3::FzfWidget::Process ;
use Gtk3::FzfWidget::Layout ;
use Gtk3::FzfWidget::FzfBackend ;
use Gtk3::FzfWidget::SocketBackend ;
use Gtk3::FzfWidget::Messages qw(msg
	MSG_LOADING
	MSG_MATCH_COUNT
	MSG_PLACEHOLDER) ;

our $VERSION = '0.01' ;

# Debug logging: set FZFW_DEBUG=1 to enable.
# Set FZFW_LOG=/path/to/file to also write to a log file.
my $_DEBUG = $ENV{FZFW_DEBUG} ? 1 : 0 ;
my $_log_fh ;

if ($_DEBUG)
	{
	binmode(STDERR, ':utf8') ;
	if ($ENV{FZFW_LOG})
		{
		open($_log_fh, '>>', $ENV{FZFW_LOG})
			or warn "FZFW: cannot open log $ENV{FZFW_LOG}: $!" ;
		if ($_log_fh) { binmode($_log_fh, ':utf8') ; $_log_fh->autoflush(1) }
		}
	}

sub _dbg
{
my ($self, $msg) = @_ ;
return unless $_DEBUG ;
require Time::HiRes ;
my ($sec, $usec) = Time::HiRes::gettimeofday() ;
my $line = sprintf "[%.3f] WIDGET: %s\n", $sec + $usec / 1e6, $msg ;
print STDERR $line ;
print $_log_fh $line if $_log_fh ;
}

# _log always writes when FZFW_LOG is set, even without FZFW_DEBUG.
# Use for key events that need tracing in production.
sub _log
{
my ($self, $msg) = @_ ;
return unless $_DEBUG || $_log_fh ;
require Time::HiRes ;
my ($sec, $usec) = Time::HiRes::gettimeofday() ;
my $line = sprintf "[%.3f] WIDGET: %s\n", $sec + $usec / 1e6, $msg ;
print STDERR $line if $_DEBUG ;
print $_log_fh $line if $_log_fh ;
}

my $widget_seq = 0 ;

my @DEFAULT_DEBOUNCE_TABLE =
	(
	[    500,  30],
	[   2000, 100],
	[  10000, 200],
	[ 100000, 350],
	[  undef, 500],
	) ;

my %SOL =
	(
	base03  => '#002b36',
	base02  => '#073642',
	base01  => '#586e75',
	base00  => '#657b83',
	base0   => '#839496',
	base1   => '#93a1a1',
	base2   => '#eee8d5',
	base3   => '#fdf6e3',
	yellow  => '#b58900',
	orange  => '#cb4b16',
	blue    => '#268bd2',
	) ;

my %THEMES =
	(
	normal =>
		{
		widget_fg            => undef,
		widget_bg            => undef,
		entry_fg             => undef,
		entry_bg             => undef,
		match_fg             => '#f39c12',
		match_bg             => undef,
		checkbox_fg          => undef,
		checkbox_bg          => undef,
		checkbox_selected_fg => '#ff0000',
		checkbox_selected_bg => undef,
		cursor_fg            => '#ffffff',
		cursor_bg            => '#2d6db5',
		border_color         => undef,
		header_fg            => undef,
		header_bg            => undef,
		info_fg              => undef,
		info_bg              => undef,
		},
	dark =>
		{
		widget_fg            => '#ffffff',
		widget_bg            => '#1e1e1e',
		entry_fg             => '#ffffff',
		entry_bg             => '#252526',
		match_fg             => '#f39c12',
		match_bg             => undef,
		checkbox_fg          => '#ffffff',
		checkbox_bg          => undef,
		checkbox_selected_fg => '#ff4444',
		checkbox_selected_bg => undef,
		cursor_fg            => '#ffffff',
		cursor_bg            => '#264f78',
		border_color         => '#3c3c3c',
		header_fg            => '#cccccc',
		header_bg            => '#252526',
		info_fg              => '#aaaaaa',
		info_bg              => '#252526',
		},
	'solarized-dark' =>
		{
		widget_fg            => $SOL{base0},
		widget_bg            => $SOL{base03},
		entry_fg             => $SOL{base0},
		entry_bg             => $SOL{base02},
		match_fg             => $SOL{yellow},
		match_bg             => undef,
		checkbox_fg          => $SOL{base1},
		checkbox_bg          => undef,
		checkbox_selected_fg => $SOL{orange},
		checkbox_selected_bg => undef,
		cursor_fg            => $SOL{base03},
		cursor_bg            => $SOL{blue},
		border_color         => $SOL{base02},
		header_fg            => $SOL{base1},
		header_bg            => $SOL{base02},
		info_fg              => $SOL{base01},
		info_bg              => $SOL{base02},
		},
	'solarized-light' =>
		{
		widget_fg            => $SOL{base00},
		widget_bg            => $SOL{base3},
		entry_fg             => $SOL{base00},
		entry_bg             => $SOL{base2},
		match_fg             => $SOL{orange},
		match_bg             => undef,
		checkbox_fg          => $SOL{base01},
		checkbox_bg          => undef,
		checkbox_selected_fg => $SOL{orange},
		checkbox_selected_bg => undef,
		cursor_fg            => $SOL{base3},
		cursor_bg            => $SOL{blue},
		border_color         => $SOL{base2},
		header_fg            => $SOL{base01},
		header_bg            => $SOL{base2},
		info_fg              => $SOL{base00},
		info_bg              => $SOL{base2},
		},
	) ;

my %DEFAULTS =
	(
	fzf_opts             => [],
	ansi                 => 0,
	highlight            => 1,
	multi                => 0,
	persistent           => 0,
	poll_ms              => 100,
	start_delay_ms       => 100,
	port                 => undef,
	initial_query        => '',
	initial_selection    => [],
	font_family          => 'Monospace',
	font_size            => 15,
	tab_width            => 8,
	width                => 'half_screen',
	height               => 'full_screen',
	min_height           => undef,
	max_height           => 'screen',
	border_width         => 2,
	theme                => 'normal',
	search_mode          => 'fuzzy',
	wrap_cursor          => 0,
	page_step            => undef,
	show_buttons         => 1,
	show_status          => 1,
	header               => undef,
	header_font_family   => undef,
	header_font_size     => undef,
	position_fn          => undef,
	info_height          => 60,
	info_font_family     => undef,
	info_font_size       => undef,
	image_max_width      => 64,
	image_max_height     => 64,
	debounce_table       => undef,
	status_format        => undef,
	row_striping         => undef,
	row_spacing          => 0,
	lazy_fetch_initial   => 50,
	lazy_fetch_page      => 50,
	lazy_fetch_threshold => 10,
	prefetch_buffer      => 100,
	transform_fn         => undef,
	image_fn             => undef,
	on_confirm           => undef,
	on_cancel            => undef,
	on_error             => undef,
	on_query_change      => undef,
	on_selection_change  => undef,
	on_cursor_change     => undef,
	on_hover             => undef,
	on_ready             => undef,
	keybindings          =>
		{
		confirm      => 'ctrl+o',
		confirm2     => 'return',
		cancel       => 'escape',
		focus_entry  => 'ctrl+q',
		clear_query  => 'ctrl+u',
		select_all   => 'ctrl+a',
		deselect_all => 'ctrl+d',
		toggle       => 'tab',
		toggle_multi => 'ctrl+m',
		cycle_theme  => 'ctrl+t',
		},
	colors               =>
		{
		widget_fg            => undef,
		widget_bg            => undef,
		entry_fg             => undef,
		entry_bg             => undef,
		match_fg             => '#f39c12',
		match_bg             => undef,
		checkbox_fg          => undef,
		checkbox_bg          => undef,
		checkbox_selected_fg => '#ff0000',
		checkbox_selected_bg => undef,
		cursor_fg            => '#ffffff',
		cursor_bg            => '#2d6db5',
		border_color         => undef,
		header_fg            => undef,
		header_bg            => undef,
		info_fg              => undef,
		info_bg              => undef,
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

$self->{instance_id}           = ++$widget_seq ;
$self->{process}               = undef ;
$self->{_backend}              = undef ;   # FzfBackend instance
$self->{_all_items}            = [] ;      # all item strings, index = original index
	$self->{_row_iters}            = [] ;      # store row -> Gtk3::TreeIter (O(1) lookup)
	$self->{_items_src}            = undef ;   # original items source (arrayref or coderef)
$self->{_match_indices}        = [] ;      # ordered arrayref of matching indices (fetched window)
$self->{_match_count}          = 0 ;       # total matches for current query
$self->{_total_count}          = 0 ;       # total items known to backend
$self->{_fetch_in_flight}      = 0 ;       # 1 while fetch_async is pending
$self->{_prefetch_at}          = 0 ;       # trigger prefetch when local_pos >= this
$self->{_load_timer}           = undef ;   # fires until all items indexed; then stops
$self->{_query_refresh_timer}  = undef ;   # fires after query change until mc stabilises
$self->{layout_obj}            = undef ;
$self->{entry}                 = undef ;
$self->{tree_view}             = undef ;
$self->{list_store}            = undef ;
$self->{scroll_win}            = undef ;
$self->{status_label}          = undef ;
$self->{info_label}            = undef ;
$self->{header_label}          = undef ;
$self->{widget_box}            = undef ;
$self->{error_label}           = undef ;
$self->{ok_button}             = undef ;
$self->{close_button}          = undef ;
$self->{pixbuf_col}            = undef ;
$self->{debounce_timer}        = undef ;
$self->{query_buffer}          = undef ;
$self->{frozen}                = 0 ;
$self->{loading}               = 0 ;
$self->{last_query}            = undef ;
$self->{local_pos}             = 0 ;
$self->{local_selected}        = {} ;
$self->{has_images}            = 0 ;

$self->{highlight}            = $config->{highlight}            // $DEFAULTS{highlight} ;
$self->{multi}                = $config->{multi}                // $DEFAULTS{multi} ;
$self->{persistent}           = $config->{persistent}           // $DEFAULTS{persistent} ;
$self->{poll_ms}              = $config->{poll_ms}              // $DEFAULTS{poll_ms} ;
$self->{fzf_opts}             = $config->{fzf_opts}             // $DEFAULTS{fzf_opts} ;
$self->{ansi}                 = $config->{ansi}                 // $DEFAULTS{ansi} ;
$self->{initial_query}        = $config->{initial_query}        // $DEFAULTS{initial_query} ;
$self->{initial_selection}    = $config->{initial_selection}    // $DEFAULTS{initial_selection} ;
$self->{start_delay_ms}       = $config->{start_delay_ms}       // $DEFAULTS{start_delay_ms} ;
$self->{port}                 = $config->{port}                 // $DEFAULTS{port} ;
$self->{font_family}          = $config->{font_family}          // $DEFAULTS{font_family} ;
$self->{font_size}            = $config->{font_size}            // $DEFAULTS{font_size} ;
$self->{tab_width}            = $config->{tab_width}            // $DEFAULTS{tab_width} ;
$self->{width}                = $config->{width}                // $DEFAULTS{width} ;
$self->{height}               = $config->{height}               // $DEFAULTS{height} ;
$self->{min_height}           = $config->{min_height}           // $DEFAULTS{min_height} ;
$self->{max_height}           = $config->{max_height}           // $DEFAULTS{max_height} ;
$self->{border_width}         = $config->{border_width}         // $DEFAULTS{border_width} ;
$self->{search_mode}          = $config->{search_mode}          // $DEFAULTS{search_mode} ;
$self->{wrap_cursor}          = $config->{wrap_cursor}          // $DEFAULTS{wrap_cursor} ;
$self->{page_step}            = $config->{page_step}            // $DEFAULTS{page_step} ;
$self->{show_buttons}         = $config->{show_buttons}         // $DEFAULTS{show_buttons} ;
$self->{show_status}          = $config->{show_status}          // $DEFAULTS{show_status} ;
$self->{header}               = $config->{header}               // $DEFAULTS{header} ;
$self->{header_font_family}   = $config->{header_font_family}   // $DEFAULTS{header_font_family} ;
$self->{header_font_size}     = $config->{header_font_size}     // $DEFAULTS{header_font_size} ;
$self->{position_fn}          = $config->{position_fn}          // $DEFAULTS{position_fn} ;
$self->{info_height}          = $config->{info_height}          // $DEFAULTS{info_height} ;
$self->{info_font_family}     = $config->{info_font_family}     // $DEFAULTS{info_font_family} ;
$self->{info_font_size}       = $config->{info_font_size}       // $DEFAULTS{info_font_size} ;
$self->{image_max_width}      = $config->{image_max_width}      // $DEFAULTS{image_max_width} ;
$self->{image_max_height}     = $config->{image_max_height}     // $DEFAULTS{image_max_height} ;
$self->{debounce_table}       = $config->{debounce_table}       // $DEFAULTS{debounce_table} ;
$self->{status_format}        = $config->{status_format}        // $DEFAULTS{status_format} ;
$self->{row_striping}          = $config->{row_striping}          // $DEFAULTS{row_striping} ;
$self->{row_spacing}           = $config->{row_spacing}           // $DEFAULTS{row_spacing} ;
$self->{prefetch_buffer}       = $config->{prefetch_buffer}       // $DEFAULTS{prefetch_buffer} ;
$self->{transform_fn}         = $config->{transform_fn}         // $DEFAULTS{transform_fn} ;
$self->{image_fn}             = $config->{image_fn}             // $DEFAULTS{image_fn} ;
$self->{on_confirm}           = $config->{on_confirm}           // $DEFAULTS{on_confirm} ;
$self->{on_cancel}            = $config->{on_cancel}            // $DEFAULTS{on_cancel} ;
$self->{on_error}             = $config->{on_error}             // $DEFAULTS{on_error} ;
$self->{on_query_change}      = $config->{on_query_change}      // $DEFAULTS{on_query_change} ;
$self->{on_selection_change}  = $config->{on_selection_change}  // $DEFAULTS{on_selection_change} ;
$self->{on_cursor_change}     = $config->{on_cursor_change}     // $DEFAULTS{on_cursor_change} ;
$self->{on_hover}             = $config->{on_hover}             // $DEFAULTS{on_hover} ;
$self->{on_ready}             = $config->{on_ready}             // $DEFAULTS{on_ready} ;

# Merge keybindings: user overrides on top of defaults
my $ukb = $config->{keybindings} // {} ;
my $dkb = $DEFAULTS{keybindings} ;
$self->{keybindings} =
	{
	confirm      => $ukb->{confirm}      // $dkb->{confirm},
	confirm2     => $ukb->{confirm2}     // $dkb->{confirm2},
	cancel       => $ukb->{cancel}       // $dkb->{cancel},
	focus_entry  => $ukb->{focus_entry}  // $dkb->{focus_entry},
	clear_query  => $ukb->{clear_query}  // $dkb->{clear_query},
	select_all   => $ukb->{select_all}   // $dkb->{select_all},
	deselect_all => $ukb->{deselect_all} // $dkb->{deselect_all},
	toggle       => $ukb->{toggle}       // $dkb->{toggle},
	toggle_multi => $ukb->{toggle_multi} // $dkb->{toggle_multi},
	cycle_theme  => $ukb->{cycle_theme}  // $dkb->{cycle_theme},
	} ;

my $theme_name = $config->{theme} // $DEFAULTS{theme} ;
my $theme      = $THEMES{$theme_name}
	or die "Unknown theme '$theme_name'. Valid themes: "
		. join(', ', sort keys %THEMES) . "\n" ;

my $uc = $config->{colors} // {} ;
$self->{_theme_name}   = $theme_name ;
$self->{_user_colors}  = $uc ;
$self->{colors} =
	{
	widget_fg            => $uc->{widget_fg}            // $theme->{widget_fg},
	widget_bg            => $uc->{widget_bg}            // $theme->{widget_bg},
	entry_fg             => $uc->{entry_fg}             // $theme->{entry_fg},
	entry_bg             => $uc->{entry_bg}             // $theme->{entry_bg},
	match_fg             => $uc->{match_fg}             // $theme->{match_fg},
	match_bg             => $uc->{match_bg}             // $theme->{match_bg},
	checkbox_fg          => $uc->{checkbox_fg}          // $theme->{checkbox_fg},
	checkbox_bg          => $uc->{checkbox_bg}          // $theme->{checkbox_bg},
	checkbox_selected_fg => $uc->{checkbox_selected_fg} // $theme->{checkbox_selected_fg},
	checkbox_selected_bg => $uc->{checkbox_selected_bg} // $theme->{checkbox_selected_bg},
	cursor_fg            => $uc->{cursor_fg}            // $theme->{cursor_fg},
	cursor_bg            => $uc->{cursor_bg}            // $theme->{cursor_bg},
	border_color         => $uc->{border_color}         // $theme->{border_color},
	header_fg            => $uc->{header_fg}            // $theme->{header_fg},
	header_bg            => $uc->{header_bg}            // $theme->{header_bg},
	info_fg              => $uc->{info_fg}              // $theme->{info_fg},
	info_bg              => $uc->{info_bg}              // $theme->{info_bg},
	} ;

# Parse keybindings into lookup structure for fast matching
$self->{_kb_map} = _parse_keybindings($self->{keybindings}) ;

my $default_layout = defined $self->{header}
	? [qw(header query list)]
	: [qw(query list)] ;

$self->_build_ui($args{layout} // $default_layout) ;
$self->_start_fzf($args{items} // []) ;

return $self ;
}

# ------------------------------------------------------------------------------
# Parse keybinding strings like 'ctrl+o', 'return', 'escape'
# into { keyval => N, ctrl => bool, shift => bool }

sub _parse_keybindings
{
my ($kb) = @_ ;

my %map ;

for my $action (keys %$kb)
	{
	my $spec  = lc($kb->{$action} // '') ;
	my $ctrl  = ($spec =~ s/ctrl\+//) ;
	my $shift = ($spec =~ s/shift\+//) ;

	my %key_names =
		(
		'return'    => Gtk3::Gdk::KEY_Return,
		'kp_enter'  => Gtk3::Gdk::KEY_KP_Enter,
		'escape'    => Gtk3::Gdk::KEY_Escape,
		'tab'       => Gtk3::Gdk::KEY_Tab,
		'home'      => Gtk3::Gdk::KEY_Home,
		'end'       => Gtk3::Gdk::KEY_End,
		'page_up'   => Gtk3::Gdk::KEY_Page_Up,
		'page_down' => Gtk3::Gdk::KEY_Page_Down,
		'up'        => Gtk3::Gdk::KEY_Up,
		'down'      => Gtk3::Gdk::KEY_Down,
		) ;

	my $keyval = $key_names{$spec} ;

	unless (defined $keyval)
		{
		# Single character key
		$keyval = Gtk3::Gdk::unicode_to_keyval(ord($spec)) if length($spec) == 1 ;
		}

	next unless defined $keyval ;

	$map{$action} =
		{
		keyval => $keyval,
		ctrl   => $ctrl  ? 1 : 0,
		shift  => $shift ? 1 : 0,
		} ;
	}

return \%map ;
}

# ------------------------------------------------------------------------------

sub _kb_matches
{
my ($self, $action, $keyval, $ctrl, $shift) = @_ ;

my $kb = $self->{_kb_map}{$action} or return 0 ;

return $keyval == $kb->{keyval}
	&& ($ctrl  ? 1 : 0) == $kb->{ctrl}
	&& ($shift ? 1 : 0) == $kb->{shift} ;
}

# ------------------------------------------------------------------------------

sub _debounce_ms
{
my ($self) = @_ ;

my $tc    = $self->{_total_count} // 0 ;
my $table = $self->{debounce_table} // \@DEFAULT_DEBOUNCE_TABLE ;

for my $row (@$table)
	{
	my ($threshold, $ms) = @$row ;
	return $ms if !defined $threshold || $tc <= $threshold ;
	}

return 500 ;
}

# ------------------------------------------------------------------------------

sub _build_ui
{
my ($self, $layout_slots) = @_ ;

my $id      = $self->{instance_id} ;
my $c       = $self->{colors} ;
my $tv_name = "fzf-list-$id" ;
my $wb_name = "fzf-wb-$id" ;
my $bb_name = "fzf-bb-$id" ;
my $sl_name = "fzf-status-$id" ;
my $hl_name = "fzf-header-$id" ;
my $il_name = "fzf-info-$id" ;

$self->{error_label} = Gtk3::Label->new('') ;
$self->{error_label}->set_line_wrap(1) ;
$self->{error_label}->set_justify('center') ;
$self->{error_label}->set_no_show_all(1) ;

$self->{widget_box} = Gtk3::Box->new('vertical', 0) ;
$self->{widget_box}->set_name($wb_name) ;

$self->{entry} = Gtk3::Entry->new() ;
$self->{entry}->set_placeholder_text(msg(MSG_PLACEHOLDER)) ;

my @css ;

# Entry colors — always include caret-color so cursor is visible
	{
	my @p ;
	push @p, "color: $c->{entry_fg}"            if $c->{entry_fg} ;
	push @p, "background-color: $c->{entry_bg}" if $c->{entry_bg} ;
	push @p, "font-family: $self->{font_family}" if $self->{font_family} ;
	push @p, "font-size: $self->{font_size}pt"   if $self->{font_size} ;
	# Ensure caret contrasts with entry background
	my $caret = $c->{entry_fg} // '#000000' ;
	push @p, "caret-color: $caret" ;
	push @css, "entry { " . join(' ; ', @p) . " }" ;
	}

# Treeview colors — scoped to instance name to avoid bleeding
if ($c->{widget_bg} || $c->{widget_fg} || $self->{font_family} || $self->{font_size})
	{
	my @p ;
	push @p, "color: $c->{widget_fg}"            if $c->{widget_fg} ;
	push @p, "background-color: $c->{widget_bg}" if $c->{widget_bg} ;
	push @p, "font-family: $self->{font_family}"  if $self->{font_family} ;
	push @p, "font-size: $self->{font_size}pt"    if $self->{font_size} ;
	push @css, "#$tv_name { " . join(' ; ', @p) . " }" ;
	}

# Row spacing — always set to suppress GTK3 default padding
push @css, "#$tv_name cell { padding-top: $self->{row_spacing}px ; padding-bottom: $self->{row_spacing}px }" ;

# Widget box and bottom bar background
push @css, "#$wb_name { background-color: $c->{widget_bg} }" if $c->{widget_bg} ;
push @css, "#$bb_name { background-color: $c->{widget_bg} ; margin: 0 ; padding: 0 }" if $c->{widget_bg} ;

# Status label color
push @css, "#$sl_name { color: $c->{widget_fg} }" if $c->{widget_fg} ;

# Header colors and font
if ($c->{header_bg} || $c->{header_fg}
	|| $self->{header_font_family} || $self->{header_font_size})
	{
	my @p ;
	push @p, "color: $c->{header_fg}"                        if $c->{header_fg} ;
	push @p, "background-color: $c->{header_bg}"             if $c->{header_bg} ;
	push @p, "font-family: $self->{header_font_family}"       if $self->{header_font_family} ;
	push @p, "font-size: $self->{header_font_size}pt"         if $self->{header_font_size} ;
	push @css, "#$hl_name { " . join(' ; ', @p) . " }" ;
	}

# Info area colors and font
if ($c->{info_bg} || $c->{info_fg}
	|| $self->{info_font_family} || $self->{info_font_size})
	{
	my @p ;
	push @p, "color: $c->{info_fg}"                        if $c->{info_fg} ;
	push @p, "background-color: $c->{info_bg}"             if $c->{info_bg} ;
	push @p, "font-family: $self->{info_font_family}"       if $self->{info_font_family} ;
	push @p, "font-size: $self->{info_font_size}pt"         if $self->{info_font_size} ;
	push @css, "#$il_name { " . join(' ; ', @p) . " }" ;
	}

# Checkbox selected colors
if ($c->{checkbox_selected_bg} || $c->{checkbox_selected_fg})
	{
	my @p ;
	push @p, "color: $c->{checkbox_selected_fg}"            if $c->{checkbox_selected_fg} ;
	push @p, "background-color: $c->{checkbox_selected_bg}" if $c->{checkbox_selected_bg} ;
	push @css, "#$tv_name check:checked { " . join(' ; ', @p) . " }" ;
	}

if (@css)
	{
	my $provider = Gtk3::CssProvider->new() ;
	$provider->load_from_data(join("\n", @css)) ;
	Gtk3::StyleContext::add_provider_for_screen(
		Gtk3::Gdk::Screen::get_default(),
		$provider,
		Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION,
		) ;
	$self->{_css_provider} = $provider ;
	}

# ListStore: col 0 = markup, col 1 = original index, col 2 = selected flag,
# col 3 = cell-background string, col 4 = cell-background-set boolean,
# col 5 = pixbuf (optional)
# Only matching rows are in the store. Row N corresponds to _match_indices[N].
$self->{list_store} = Gtk3::ListStore->new(
	'Glib::String', 'Glib::Int', 'Glib::Boolean',
	'Glib::String', 'Glib::Boolean', 'Gtk3::Gdk::Pixbuf',
	) ;

$self->{tree_view} = Gtk3::TreeView->new_with_model($self->{list_store}) ;
$self->{tree_view}->set_name($tv_name) ;
$self->{tree_view}->set_headers_visible(0) ;
$self->{tree_view}->set_enable_search(0) ;
$self->{tree_view}->get_selection()->set_mode('single') ;

# Set row height via fixed-height mode when using images
if ($self->{image_fn})
	{
	$self->{tree_view}->set_fixed_height_mode(1) ;
	}

# Checkbox column — always created, visible only in multi mode
	{
	my $toggle_col  = Gtk3::TreeViewColumn->new() ;
	my $toggle_cell = Gtk3::CellRendererToggle->new() ;
	$toggle_cell->set(activatable => 0) ;
	$toggle_cell->set(cell_background => $c->{checkbox_bg}) if $c->{checkbox_bg} ;
	$toggle_col->pack_start($toggle_cell, 0) ;
	$toggle_col->add_attribute($toggle_cell, 'active', 2) ;
	$toggle_col->set_sizing('fixed') if $self->{image_fn} ;
	$toggle_col->set_visible($self->{multi} ? 1 : 0) ;
	$self->{tree_view}->append_column($toggle_col) ;
	$self->{_toggle_col} = $toggle_col ;
	}

# Pixbuf column — created but hidden until image_fn confirms images exist
$self->{pixbuf_col} = Gtk3::TreeViewColumn->new() ;
my $pixbuf_cell     = Gtk3::CellRendererPixbuf->new() ;
$pixbuf_cell->set('width'  => $self->{image_max_width}) ;
$pixbuf_cell->set('height' => $self->{image_max_height}) ;
$self->{pixbuf_col}->pack_start($pixbuf_cell, 0) ;
$self->{pixbuf_col}->add_attribute($pixbuf_cell, 'pixbuf', 5) ;
$self->{pixbuf_col}->set_visible(0) ;
$self->{pixbuf_col}->set_sizing('fixed') if $self->{image_fn} ;
$self->{tree_view}->append_column($self->{pixbuf_col}) ;

# Text column — markup from col 0; background via cell-data-func (no store columns)
my $text_col  = Gtk3::TreeViewColumn->new() ;
my $text_cell = Gtk3::CellRendererText->new() ;

if ($self->{font_family} || $self->{font_size})
	{
	my $font_desc = '' ;
	$font_desc .= $self->{font_family}     if $self->{font_family} ;
	$font_desc .= ' ' . $self->{font_size} if $self->{font_size} ;
	$text_cell->set('font' => $font_desc) ;
	}

$text_col->pack_start($text_cell, 1) ;
$text_col->add_attribute($text_cell, 'markup', 0) ;
$text_col->add_attribute($text_cell, 'cell-background', 3) ;
$text_col->add_attribute($text_cell, 'cell-background-set', 4) ;

$text_col->set_expand(1) ;
$text_col->set_sizing('fixed') if $self->{image_fn} ;
$self->{tree_view}->append_column($text_col) ;

$self->{scroll_win} = Gtk3::ScrolledWindow->new(undef, undef) ;
$self->{scroll_win}->set_policy('never', 'automatic') ;
$self->{scroll_win}->add($self->{tree_view}) ;

# Status label
$self->{status_label} = Gtk3::Label->new('') ;
$self->{status_label}->set_name($sl_name) ;
$self->{status_label}->set_xalign(0) ;
my $sl_provider = Gtk3::CssProvider->new() ;
$sl_provider->load_from_data('label { font-size: 10pt }') ;
$self->{status_label}->get_style_context()->add_provider(
	$sl_provider, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION) ;

# Info area (for on_hover output) — shown only when on_hover is set
if ($self->{on_hover})
	{
	$self->{info_label} = Gtk3::Label->new('') ;
	$self->{info_label}->set_name($il_name) ;
	$self->{info_label}->set_xalign(0) ;
	$self->{info_label}->set_line_wrap(1) ;
	$self->{info_label}->set_size_request(-1, $self->{info_height}) ;
	}

# Layout
$self->{layout_obj} = Gtk3::FzfWidget::Layout->new(slots => $layout_slots) ;

my %layout_widgets = (query => $self->{entry}, list => $self->{scroll_win}) ;

if (defined $self->{header})
	{
	my $htext = $self->{header} ;
	$htext    = decode_utf8($htext) unless is_utf8($htext) ;
	$self->{header_label} = Gtk3::Label->new($htext) ;
	$self->{header_label}->set_name($hl_name) ;
	$self->{header_label}->set_xalign(0) ;

	# Apply font via CSS — more portable than Pango API across GTK3 Perl versions
	if ($self->{header_font_family} || $self->{header_font_size})
		{
		my @hprops ;
		push @hprops, "font-family: $self->{header_font_family}" if $self->{header_font_family} ;
		push @hprops, "font-size: $self->{header_font_size}pt"   if $self->{header_font_size} ;
		my $hprovider = Gtk3::CssProvider->new() ;
		$hprovider->load_from_data("#$hl_name { " . join(' ; ', @hprops) . " }") ;
		$self->{header_label}->get_style_context()->add_provider(
			$hprovider, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION) ;
		}

	$layout_widgets{header} = $self->{header_label} ;
	}

$self->{layout_obj}->build($self->{widget_box}, \%layout_widgets) ;

# Info area packed between list and bottom bar
if ($self->{on_hover})
	{
	$self->{widget_box}->pack_end($self->{info_label}, 0, 0, 0) ;
	}

# Buttons
$self->{ok_button}    = Gtk3::Button->new('OK') ;
$self->{close_button} = Gtk3::Button->new('Close') ;

my $btn_provider = Gtk3::CssProvider->new() ;
$btn_provider->load_from_data(
	'button { padding: 1px 4px ; min-height: 0 ; min-width: 0 } button label { padding: 0 }') ;

for my $btn ($self->{ok_button}, $self->{close_button})
	{
	$btn->get_style_context()->add_provider($btn_provider, 800) ;
	}

$self->{ok_button}->signal_connect(clicked => sub { $self->_confirm() }) ;
$self->{close_button}->signal_connect(clicked => sub { $self->_cancel() }) ;

# Bottom bar: status left, buttons right
my $bottom_bar = Gtk3::Box->new('horizontal', 4) ;
$bottom_bar->set_name($bb_name) ;
$self->{bottom_bar} = $bottom_bar ;

if ($self->{show_status})
	{
	$bottom_bar->pack_start($self->{status_label}, 1, 1, 0) ;
	}

if ($self->{show_buttons})
	{
	$bottom_bar->pack_end($self->{ok_button},    0, 0, 2) ;
	$bottom_bar->pack_end($self->{close_button}, 0, 0, 2) ;
	}

$self->{widget_box}->pack_end($bottom_bar, 0, 0, 0) ;

$self->pack_start($self->{widget_box},  1, 1, 0) ;
$self->pack_start($self->{error_label}, 0, 0, 0) ;

$self->_connect_signals() ;
$self->show_all() ;
$self->{error_label}->hide() ;
}

# ------------------------------------------------------------------------------

sub _connect_signals
{
my ($self) = @_ ;

$self->{entry}->signal_connect(changed => sub { $self->_on_entry_changed() }) ;

$self->{tree_view}->signal_connect(
	'row-activated',
	sub
		{
		my ($tv, $path, $col) = @_ ;

		# path is in filter-model space
		my $filter_row = $path->to_string() + 0 ;
		my $orig_idx   = $self->{_match_indices}[$filter_row] ;
		return unless defined $orig_idx ;

		my $old_pos        = $self->{local_pos} ;
		$self->{local_pos} = $filter_row ;
		$self->_redraw_cursor($old_pos, $filter_row) ;
		$self->_confirm() ;
		},
	) ;

# Single click in multi mode toggles the clicked row.
# Clicking the checkbox, the text, or anywhere on the row all count.
if ($self->{multi})
	{
	$self->{tree_view}->signal_connect(
		'button-press-event',
		sub
			{
			my ($tv, $event) = @_ ;

			return 0 unless $event->type eq 'button-press' ;
			return 0 unless $event->button == 1 ;

			my $x = int($event->x) ;
			my $y = int($event->y) ;

			my ($path, $col, $cx, $cy) = $tv->get_path_at_pos($x, $y) ;
			return 0 unless defined $path ;

			my $filter_row = $path->to_string() + 0 ;
			my $orig_idx   = $self->{_match_indices}[$filter_row] ;
			return 0 unless defined $orig_idx ;

			my $old_pos = $self->{local_pos} ;
			my $old_sel = { %{$self->{local_selected}} } ;

			if ($self->{local_selected}{$orig_idx})
				{
				delete $self->{local_selected}{$orig_idx} ;
				}
			else
				{
				$self->{local_selected}{$orig_idx} = 1 ;
				}

			$self->{local_pos} = $filter_row ;
			$self->_redraw_cursor($old_pos, $filter_row) ;
			$self->_update_status_label() ;

			my $text = $self->{_all_items}[$orig_idx] // '' ;
			$self->_maybe_fire_selection_change(
				$old_sel, $orig_idx,
				$self->{local_selected}{$orig_idx} ? 1 : 0,
				$text) ;

			return 1 ;
			},
		) ;
	}

# Mouse motion for on_hover
if ($self->{on_hover})
	{
	$self->{tree_view}->add_events(['pointer-motion-mask']) ;
	$self->{tree_view}->signal_connect(
		'motion-notify-event',
		sub
			{
			my ($tv, $event) = @_ ;
			my $x = int($event->x) ;
			my $y = int($event->y) ;
			my ($path, $col, $cx, $cy) = $tv->get_path_at_pos($x, $y) ;
			return 0 unless defined $path ;
			my $filter_row = $path->to_string() + 0 ;
			my $orig_idx   = $self->{_match_indices}[$filter_row] ;
			return 0 unless defined $orig_idx ;
			my $text = $self->{_all_items}[$orig_idx] // '' ;
			my $info = $self->{on_hover}->($self, $text, $orig_idx) ;
			$self->{info_label}->set_text($info // '') if $self->{info_label} ;
			return 0 ;
			},
		) ;
	}

$self->signal_connect(destroy => sub { $self->_cleanup() }) ;

$self->signal_connect(
	realize => sub
		{
		my $win = $self->get_toplevel() ;
		return unless $win && $win->isa('Gtk3::Window') ;

		my $screen = Gtk3::Gdk::Screen::get_default() ;
		my $sw     = $screen->get_width() ;
		my $sh     = $screen->get_height() ;

		my $w = $self->{width} ;
		my $h = $self->{height} ;

		$w = int($sw / 2) if !defined $w || $w eq 'half_screen' ;
		$h = $sh          if !defined $h || $h eq 'full_screen' ;
		$w = $sw          if defined $w  && $w eq 'full_screen' ;
		$w = $sw          if defined $w  && $w > $sw ;
		$h = $sh          if defined $h  && $h > $sh ;

		$h = $self->{min_height} if defined $self->{min_height} && $h < $self->{min_height} ;

		my $max_h = $self->{max_height} ;
		if (defined $max_h)
			{
			$max_h = $sh if $max_h eq 'screen' ;
			$h = $max_h  if $h > $max_h ;
			}

		$win->set_default_size($w, $h) ;
		$win->resize($w, $h) ;
		$win->set_border_width($self->{border_width}) if defined $self->{border_width} ;

		if ($self->{colors}{border_color} && $self->{border_width})
			{
			my $provider = Gtk3::CssProvider->new() ;
			$provider->load_from_data(
				"window { background-color: $self->{colors}{border_color} }") ;
			$win->get_style_context()->add_provider(
				$provider, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION) ;
			}

		$win->signal_connect(
			'key-press-event',
			sub { $self->_on_window_key_press($_[1]) },
			) ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub _on_entry_changed
{
my ($self) = @_ ;

return if $self->{frozen} ;

if ($self->{loading})
	{
	$self->{query_buffer} = $self->{entry}->get_text() ;
	return ;
	}

Glib::Source->remove($self->{debounce_timer}) if $self->{debounce_timer} ;

my $ms = $self->_debounce_ms() ;

$self->{debounce_timer} = Glib::Timeout->add(
	$ms,
	sub
		{
		$self->{debounce_timer} = undef ;
		$self->_send_query() ;
		return 0 ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub _send_query
{
my ($self) = @_ ;

return unless $self->{_backend} ;

my $query = $self->{entry}->get_text() ;

$self->_dbg("QUERY_CHANGE q='$query' backend=" . ref($self->{_backend})) ;
$self->{on_query_change}->($self, $query) if $self->{on_query_change} ;

# Stop both timers — they share the StatePoller with query_async.
$self->_stop_load_timer() ;
$self->_stop_query_refresh_timer() ;

$self->{_fetch_in_flight} = 0 ;

# Cancel any in-flight StatePoller request so the query GET is not skipped.
$self->{_backend}->cancel() if $self->{_backend}->can('cancel') ;

$self->_query_backend($query) ;
}

# ------------------------------------------------------------------------------

sub _on_window_key_press
{
my ($self, $event) = @_ ;

my $keyval = $event->keyval() ;
my $state  = ${$event->get_state()} ;
my $ctrl   = ($state & 4) ? 1 : 0 ;
my $shift  = ($state & 1) ? 1 : 0 ;

if ($self->_kb_matches('cancel', $keyval, $ctrl, $shift))
	{
	$self->_cancel() ;
	return 1 ;
	}

if ($self->_kb_matches('confirm', $keyval, $ctrl, $shift)
	|| $self->_kb_matches('confirm2', $keyval, $ctrl, $shift))
	{
	$self->_confirm() ;
	return 1 ;
	}

if ($self->_kb_matches('focus_entry', $keyval, $ctrl, $shift))
	{
	$self->{entry}->grab_focus() ;
	$self->{entry}->set_position(-1) ;
	return 1 ;
	}

if ($self->_kb_matches('clear_query', $keyval, $ctrl, $shift))
	{
	$self->{entry}->set_text('') ;
	return 1 ;
	}

if ($self->_kb_matches('select_all', $keyval, $ctrl, $shift))
	{
	if ($self->{multi})
		{
		my $old_sel = { %{$self->{local_selected}} } ;

		$self->{local_selected} = { map { $_ => 1 } @{$self->{_match_indices}} } ;

		$self->_redraw_cursor($self->{local_pos}, $self->{local_pos}) ;
		$self->_update_status_label() ;

		if ($self->{on_selection_change})
			{
			my @sel = map { [$self->{_all_items}[$_] // '', $_] }
				@{$self->{_match_indices}} ;
			$self->{on_selection_change}->($self, \@sel, undef, 1, undef) ;
			}
		}

	return 1 ;
	}

if ($self->_kb_matches('deselect_all', $keyval, $ctrl, $shift))
	{
	if ($self->{multi})
		{
		$self->{local_selected} = {} ;

		$self->_redraw_cursor($self->{local_pos}, $self->{local_pos}) ;
		$self->_update_status_label() ;

		$self->{on_selection_change}->($self, [], undef, 0, undef)
			if $self->{on_selection_change} ;
		}

	return 1 ;
	}

if ($self->_kb_matches('toggle_multi', $keyval, $ctrl, $shift))
	{
	$self->_toggle_multi() ;
	return 1 ;
	}

if ($self->_kb_matches('cycle_theme', $keyval, $ctrl, $shift))
	{
	$self->_cycle_theme() ;
	return 1 ;
	}

if ($keyval == Gtk3::Gdk::KEY_Down)
	{
	$self->_navigate(1) ;
	return 1 ;
	}

if ($keyval == Gtk3::Gdk::KEY_Up)
	{
	$self->_navigate(-1) ;
	return 1 ;
	}

if ($keyval == Gtk3::Gdk::KEY_Page_Down)
	{
	my $step = $self->{page_step} // $self->_visible_row_count() ;
	$self->_navigate($step) ;
	return 1 ;
	}

if ($keyval == Gtk3::Gdk::KEY_Page_Up)
	{
	my $step = $self->{page_step} // $self->_visible_row_count() ;
	$self->_navigate(-$step) ;
	return 1 ;
	}

if ($ctrl && $keyval == Gtk3::Gdk::KEY_Home)
	{
	$self->_navigate(-9999) ;
	return 1 ;
	}

if ($ctrl && $keyval == Gtk3::Gdk::KEY_End)
	{
	$self->_navigate(9999) ;
	return 1 ;
	}

if ($self->{multi} && $self->_kb_matches('toggle', $keyval, $ctrl, $shift))
	{
	my $pos      = $self->{local_pos} ;
	my $orig_idx = $self->{_match_indices}[$pos] ;

	if (defined $orig_idx)
		{
		my $old_sel = { %{$self->{local_selected}} } ;

		if ($self->{local_selected}{$orig_idx})
			{ delete $self->{local_selected}{$orig_idx} }
		else
			{ $self->{local_selected}{$orig_idx} = 1 }

		my $count   = scalar @{$self->{_match_indices}} ;
		my $new_pos = $pos + 1 ;
		$new_pos = $self->{wrap_cursor} ? 0 : $count - 1 if $new_pos >= $count ;

		$self->{local_pos} = $new_pos ;
		$self->_redraw_cursor($pos, $new_pos) ;
		$self->_scroll_to($new_pos, $pos) ;
		$self->_update_status_label() ;

		my $text = $self->{_all_items}[$orig_idx] // '' ;
		$self->_maybe_fire_selection_change(
			$old_sel, $orig_idx,
			$self->{local_selected}{$orig_idx} ? 1 : 0,
			$text) ;
		}
	return 1 ;
	}

return 0 ;
}

# ------------------------------------------------------------------------------

sub _navigate
{
my ($self, $delta) = @_ ;

my $count = scalar @{$self->{_match_indices}} ;
return unless $count ;

my $old_pos = $self->{local_pos} ;
my $new_pos = $old_pos + $delta ;

if ($self->{wrap_cursor})
	{
	$new_pos = $new_pos % $count ;
	$new_pos += $count if $new_pos < 0 ;
	}
else
	{
	$new_pos = 0          if $new_pos < 0 ;
	$new_pos = $count - 1 if $new_pos >= $count ;
	}

# Preemptive prefetch: when cursor reaches _prefetch_at, start fetching
# more indices in the background before the display end is reached.
if ($delta > 0
	&& $new_pos >= $self->{_prefetch_at}
	&& $count < $self->{_match_count}
	&& !$self->{_fetch_in_flight})
	{
	$self->_dbg("navigate: prefetch triggered at pos=$new_pos prefetch_at=$self->{_prefetch_at} fetched=$count mc=$self->{_match_count}") ;
	$self->_prefetch_more() ;
	}

# If we are at the very last fetched row and a fetch is in flight, pump
# the event loop briefly so the display doesn't freeze.
if ($new_pos == $count - 1 && $count < $self->{_match_count} && $self->{_fetch_in_flight})
	{
	$self->_dbg("navigate: at last row, fetch in flight — pumping event loop") ;
	my $deadline = time() + 0.5 ;
	while ($self->{_fetch_in_flight} && time() < $deadline)
		{
		Glib::MainContext->default->iteration(0) ;
		}
	# Re-read count after pump — may have grown
	$count   = scalar @{$self->{_match_indices}} ;
	my $desired = $old_pos + $delta ;
	$new_pos = $desired < $count ? $desired : $count - 1 ;
	}

return if $new_pos == $old_pos ;

$self->{local_pos} = $new_pos ;
$self->_dbg("navigate: old=$old_pos new=$new_pos fetched=$count mc=$self->{_match_count}") ;
$self->_redraw_cursor($old_pos, $new_pos) ;
$self->_scroll_to($new_pos, $old_pos) ;

if ($self->{on_cursor_change})
	{
	my $orig_idx = $self->{_match_indices}[$new_pos] ;
	if (defined $orig_idx)
		{
		my $text = $self->{_all_items}[$orig_idx] // '' ;
		$self->{on_cursor_change}->($self, $text, $orig_idx) ;
		}
	}
}

# ------------------------------------------------------------------------------

sub _visible_row_count
{
my ($self) = @_ ;
my ($start, $end) = $self->{tree_view}->get_visible_range() ;
return 10 unless defined $start && defined $end ;
return $end->to_string() - $start->to_string() + 1 ;
}

# ------------------------------------------------------------------------------

sub _scroll_to
{
my ($self, $new_pos, $old_pos) = @_ ;

my $cursor_path = Gtk3::TreePath->new_from_string("$new_pos") ;
my $going_down  = ($new_pos > $old_pos) ? 1 : 0 ;
my $row_align   = $going_down ? 1.0 : 0.0 ;

my ($vis_start, $vis_end) = $self->{tree_view}->get_visible_range() ;
my $vis_start_i = defined $vis_start ? $vis_start->to_string() + 0 : 0 ;
my $vis_end_i   = defined $vis_end   ? $vis_end->to_string()   + 0 : 0 ;

if ($new_pos < $vis_start_i || $new_pos > $vis_end_i)
	{
	$self->{tree_view}->scroll_to_cell($cursor_path, undef, 1, $row_align, 0.0) ;
	}
}

# ------------------------------------------------------------------------------
# Redraw the two rows affected by a cursor move (old and new position).
# Uses filter-model row numbers.  Triggers a cell-data-func repaint by
# invalidating the markup column on those two store rows.

sub _redraw_cursor
{
my ($self, $old_pos, $new_pos) = @_ ;

# Store row = filter-model row (plain ListStore, no filter).
# Only update the two rows that changed: old cursor and new cursor.
my $query = $self->{entry}->get_text() ;
my $store = $self->{list_store} ;
my $c     = $self->{colors} ;
my $stripe = $self->{row_striping} ;

for my $row ($old_pos, $new_pos)
	{
	next if $row < 0 ;
	my $orig_idx = $self->{_match_indices}[$row] ;
	next unless defined $orig_idx ;

	my $iter = $self->{_row_iters}[$row] ;
	next unless $iter ;

	my $text    = $self->{_all_items}[$orig_idx] // '' ;
	my $display = $self->{transform_fn}
		? ($self->{transform_fn}->($text) // $text)
		: $text ;
	my $is_cursor = ($row == $self->{local_pos}) ? 1 : 0 ;
	my $markup    = $self->_make_markup(
		$display,
		$self->_get_positions($display, $query),
		$is_cursor, undef, $text,
		) ;
	my $cell_bg = $is_cursor
		? ($c->{cursor_bg} // '#2d6db5')
		: ($stripe ? $stripe->[$row % scalar @$stripe] : undef) ;

	$store->set($iter, 0, $markup, 3, $cell_bg // '', 4, $cell_bg ? 1 : 0) ;
	$store->set($iter, 2, ($self->{local_selected}{$orig_idx} ? 1 : 0))
		if $self->{multi} ;
	}
}

# ------------------------------------------------------------------------------
# Query the backend for a new set of matching indices.
# Called when the query changes (via debounce) or on initial load.

sub _query_backend
{
my ($self, $query) = @_ ;

return unless $self->{_backend} ;
return if $self->{frozen} ;

# Always fetch prefetch_buffer*2 rows on a query change — never re-use
# the previous match count as limit, which would return indices from
# the old query's population.
my $limit = $self->{prefetch_buffer} * 2 ;

$self->_dbg("query_backend: q='$query' limit=$limit") ;

$self->{_backend}->query_async($query, $limit, sub
	{
	my ($matches, $mc, $tc) = @_ ;
	return if $self->{frozen} ;

	unless ($matches)
		{
		$self->_dbg("query_backend: backend returned undef") ;
		return ;
		}

	$self->_dbg("query_backend: got " . scalar(@$matches) . " matches mc=$mc tc=$tc") ;
	$self->_apply_query_result($matches, $mc, $tc, $query) ;
	}) ;
}

# ------------------------------------------------------------------------------
# Apply a fresh set of matching indices from the backend.
# Resets local_pos, updates filter, redraws.

sub _apply_query_result
{
my ($self, $matches, $mc, $tc, $query) = @_ ;

# Clear selection when query changes
$self->{local_selected} = {}
	if ($self->{last_query} // '') ne $query ;

$self->{last_query}     = $query ;
$self->{_match_count}   = $mc ;
$self->{_total_count}   = $tc ;
$self->{_match_indices} = [ map { $_->{index} } @$matches ] ;
	# Cache text from fzf response into _all_items for immediate display.
	for my $m (@$matches)
		{
		my $idx = $m->{index} ;
		$self->{_all_items}[$idx] //= $m->{text}
			if defined $idx && defined $m->{text} && length($m->{text}) ;
		}
$self->{local_pos}      = 0 ;

my $fetched = scalar @{$self->{_match_indices}} ;
$self->{_prefetch_at} = $fetched - $self->{prefetch_buffer} ;
$self->{_prefetch_at} = 0 if $self->{_prefetch_at} < 0 ;

$self->_dbg("apply_query_result: fetched=$fetched mc=$mc prefetch_at=$self->{_prefetch_at} match_indices=[" . join(',', @{$self->{_match_indices}}[0..($fetched>5?4:$fetched-1)]) . ($fetched>5?'...' : '') . "]") ;
warn "FZFW apply_query_result: q='$query' mc=$mc fetched=$fetched\n" if $ENV{FZFW_TRACE} ;

my $item_count = scalar @{$self->{_all_items}} ;
if ($self->{_load_timer} && $item_count > 0 && $tc >= $item_count)
	{
	$self->_dbg("apply_query_result: all items indexed — stopping load timer") ;
	$self->_stop_load_timer() ;
	}

# Rebuild the store: clear and insert only the matching rows.
$self->_rebuild_store($query) ;

$self->_update_status_label() ;
$self->{tree_view}->scroll_to_point(0, 0) if $fetched > 0 ;

# Restart the refresh timer so it keeps fetching updated results as fzf
# finishes computing.  Stops when matchCount stabilises.
$self->_start_query_refresh_timer($query) ;
}

# ------------------------------------------------------------------------------
# Query refresh timer — fires after a query change to fetch updated results
# as fzf progressively computes matches for the current query.
# Stops when matchCount is stable across two consecutive polls.

sub _start_query_refresh_timer
{
my ($self, $query) = @_ ;

$self->_stop_query_refresh_timer() ;

my $prev_mc   = $self->{_match_count} ;
my $stable    = 0 ;

$self->_dbg("start_query_refresh_timer: q='$query' initial_mc=$prev_mc") ;

$self->{_query_refresh_timer} = Glib::Timeout->add(
	$self->{poll_ms},
	sub
		{
		return 0 unless $self->{_backend} ;
		return 1 if $self->{frozen} ;
		return 0 if ($self->{last_query} // '') ne $query ;
		return 1 if $self->{_fetch_in_flight} ;

		# Fetch everything we know matches — grow window to full match count
		my $want = $self->{_match_count} > 0
			? $self->{_match_count}
			: $self->{prefetch_buffer} * 2 ;

		# Cap at a reasonable single-request size to avoid blocking too long
		my $cap = 5000 ;
		my $already = scalar @{$self->{_match_indices}} ;
		if ($want > $already + $cap) { $want = $already + $cap }

		$self->{_backend}->fetch_async($want, sub
			{
			my ($matches, $mc, $tc) = @_ ;
			return unless defined $mc ;
			return if ($self->{last_query} // '') ne $query ;

			$self->{_total_count} = $tc ;

			my $new_fetched = scalar @{$matches // []} ;

			if ($mc != $prev_mc || $new_fetched > $already)
				{
				$self->_dbg("query_refresh: mc=$mc (was $prev_mc) fetched=$new_fetched (was $already) — rebuilding") ;
				$stable  = 0 ;
				$prev_mc = $mc ;

				$self->{_match_count}   = $mc ;
				$self->{_match_indices} = [ map { $_->{index} } @{$matches // []} ] ;

				for my $m (@{$matches // []})
					{
					my $idx = $m->{index} ;
					$self->{_all_items}[$idx] //= $m->{text}
						if defined $idx && defined $m->{text} && length($m->{text}) ;
					}

				my $fetched = scalar @{$self->{_match_indices}} ;
				$self->{_prefetch_at} = $fetched - $self->{prefetch_buffer} ;
				$self->{_prefetch_at} = 0 if $self->{_prefetch_at} < 0 ;

				$self->_rebuild_store($query) ;
				$self->_update_status_label() ;
				}
			else
				{
				$stable++ ;
				$self->_dbg("query_refresh: stable $stable/3 mc=$mc fetched=$new_fetched") ;
				}
			}) ;

		if ($stable >= 3)
			{
			$self->_dbg("query_refresh: stopping — mc stable at $prev_mc") ;
			$self->{_query_refresh_timer} = undef ;
			return 0 ;
			}

		return 1 ;
		},
	) ;
}

sub _stop_query_refresh_timer
{
my ($self) = @_ ;

if ($self->{_query_refresh_timer})
	{
	Glib::Source->remove($self->{_query_refresh_timer}) ;
	$self->{_query_refresh_timer} = undef ;
	}
}

# ------------------------------------------------------------------------------
# Prefetch more matching indices when cursor approaches the loaded window end.

sub _prefetch_more
{
my ($self) = @_ ;

return if $self->{_fetch_in_flight} ;
return unless $self->{_backend} ;

my $current = scalar @{$self->{_match_indices}} ;
my $want    = $current + $self->{prefetch_buffer} ;

$self->{_fetch_in_flight} = 1 ;
$self->_dbg("prefetch_more: current=$current want=$want mc=$self->{_match_count}") ;

$self->{_backend}->fetch_async($want, sub
	{
	my ($matches, $mc, $tc) = @_ ;

	$self->{_fetch_in_flight} = 0 ;

	unless ($matches)
		{
		$self->_dbg("prefetch_more: backend returned undef") ;
		return ;
		}

	my $old_count = scalar @{$self->{_match_indices}} ;
	$self->{_match_count} = $mc ;
	$self->{_total_count} = $tc ;
	$self->{_match_indices} = [ map { $_->{index} } @$matches ] ;

	my $new_count = scalar @{$self->{_match_indices}} ;
	$self->{_prefetch_at} = $new_count - $self->{prefetch_buffer} ;
	$self->{_prefetch_at} = 0 if $self->{_prefetch_at} < 0 ;

	$self->{local_pos} = $new_count - 1
		if $self->{local_pos} >= $new_count && $new_count > 0 ;

	$self->_dbg("prefetch_more: got $new_count (was $old_count) mc=$mc") ;

	if ($new_count > $old_count)
		{
		my $query = $self->{entry}->get_text() ;
		my $store = $self->{list_store} ;
		my $stripe = $self->{row_striping} ;

		for my $row ($old_count .. $new_count - 1)
			{
			my $orig_idx = $self->{_match_indices}[$row] ;
			next unless defined $orig_idx ;
			my $text    = $self->{_all_items}[$orig_idx] // '' ;
			my $display = $self->{transform_fn}
				? ($self->{transform_fn}->($text) // $text)
				: $text ;
			my $markup  = $self->_make_markup(
				$display, $self->_get_positions($display, $query),
				0, undef, $text,
				) ;
			my $cell_bg = $stripe
				? $stripe->[$row % scalar @$stripe]
				: undef ;
			my $iter = $store->append() ;
			$store->set($iter,
				0, $markup,
				1, $orig_idx,
				2, ($self->{local_selected}{$orig_idx} ? 1 : 0),
				3, $cell_bg // '',
				4, $cell_bg ? 1 : 0,
				) ;
			$self->{_row_iters}[$row] = $iter ;
			}

		$self->_update_status_label() ;
		}
	}) ;
}
# ------------------------------------------------------------------------------
# Rebuild markup for all currently visible (matching) rows.
# Called after query changes when all rows need new highlight positions.

sub _rebuild_store
{
my ($self, $query) = @_ ;

$query //= $self->{entry}->get_text() ;
my $store  = $self->{list_store} ;
my $c      = $self->{colors} ;
my $stripe = $self->{row_striping} ;

my $n = scalar @{$self->{_match_indices}} ;
$self->_dbg("rebuild_store: n=$n query='$query' store_rows_before=" . $store->iter_n_children(undef)) ;
warn "FZFW rebuild_store: n=$n query='$query'\n" if $ENV{FZFW_TRACE} ;

$store->clear() ;
$self->{_row_iters} = [] ;   # row -> Gtk3::TreeIter, O(1) lookup

for my $row (0 .. $#{$self->{_match_indices}})
	{
	my $orig_idx = $self->{_match_indices}[$row] ;
	next unless defined $orig_idx ;

	my $text    = $self->{_all_items}[$orig_idx] // '' ;
	my $display = $self->{transform_fn}
		? ($self->{transform_fn}->($text) // $text)
		: $text ;
	my $is_cursor = ($row == $self->{local_pos}) ? 1 : 0 ;
	my $markup    = $self->_make_markup(
		$display,
		$self->_get_positions($display, $query),
		$is_cursor, undef, $text,
		) ;
	my $cell_bg = $is_cursor
		? ($c->{cursor_bg} // '#2d6db5')
		: ($stripe ? $stripe->[$row % scalar @$stripe] : undef) ;

	my $iter = $store->append() ;
	$store->set($iter,
		0, $markup,
		1, $orig_idx,
		2, ($self->{local_selected}{$orig_idx} ? 1 : 0),
		3, $cell_bg // '',
		4, $cell_bg ? 1 : 0,
		) ;
	$self->{_row_iters}[$row] = $iter ;

	if ($self->{image_fn})
		{
		my $pb = $self->{image_fn}->($text, $orig_idx) ;
		if (defined $pb)
			{
			$store->set($iter, 5, $pb) ;
			$self->{has_images} = 1 ;
			$self->{pixbuf_col}->set_visible(1) ;
			}
		}
	}
}
# ------------------------------------------------------------------------------
# Initial load timer — fires every poll_ms until backend has indexed all items.
# Stops itself once total_count equals item count.

sub _start_load_timer
{
my ($self) = @_ ;

$self->_stop_load_timer() ;

my $total_items = scalar @{$self->{_all_items}} ;
my $_prev_tc    = 0 ;

# If the backend already reports all items indexed (e.g. MockBackend or
# fzf responded quickly), no timer is needed.
return if $self->{_backend} && $self->{_backend}->total_count() >= $total_items ;

$self->_dbg("start_load_timer: waiting for $total_items items") ;

$self->{_load_timer} = Glib::Timeout->add(
	$self->{poll_ms} * 2,
	sub
		{
		return 0 unless $self->{_backend} ;
		return 1 if $self->{frozen} ;

		# Stop once the backend confirms all items are indexed.
		# For arrayref sources: stop when tc >= total_items.
		# For coderef sources (_all_items empty): stop when tc stops growing.
		if ($total_items > 0 && $self->{_total_count} >= $total_items)
			{
			$self->_dbg("load_timer: all $total_items items indexed — stopping") ;
			$self->{_load_timer} = undef ;
			return 0 ;
			}

		if ($total_items == 0 && $self->{_total_count} > 0 && $self->{_total_count} == $_prev_tc)
			{
			$self->_dbg("load_timer: tc stable at $self->{_total_count} — stopping") ;
			$self->{_load_timer} = undef ;
			return 0 ;
			}
		$_prev_tc = $self->{_total_count} ;

		# Don't fetch if _send_query just fired — that request takes priority.
		return 1 if $self->{_fetch_in_flight} ;

		# Fire a lightweight fetch to update _total_count and _match_count.
		$self->{_backend}->fetch_async($self->{prefetch_buffer} * 2, sub
			{
			my ($m, $mc, $tc) = @_ ;
			return unless defined $tc ;
			$self->{_total_count} = $tc ;

			return unless defined $mc && $mc != $self->{_match_count} ;
			return unless $m && @$m ;

			my @new_indices = map { $_->{index} } @$m ;

			# Don't replace the current window if it would invalidate local_pos.
			return if scalar(@new_indices) <= $self->{local_pos} ;

			$self->{_match_count}   = $mc ;
			$self->{_match_indices} = \@new_indices ;
			my $fetched = scalar @new_indices ;
			$self->{_prefetch_at} = $fetched - $self->{prefetch_buffer} ;
			$self->{_prefetch_at} = 0 if $self->{_prefetch_at} < 0 ;
			$self->_rebuild_store() ;
			$self->_update_status_label() ;
			}) ;

		return 1 ;
		},
	) ;
}

sub _stop_load_timer
{
my ($self) = @_ ;

if ($self->{_load_timer})
	{
	Glib::Source->remove($self->{_load_timer}) ;
	$self->{_load_timer} = undef ;
	}
}

# ------------------------------------------------------------------------------

sub _update_status_label
{
my ($self) = @_ ;

return unless $self->{show_status} ;

my $mc  = $self->{_match_count}  // 0 ;
my $tc  = $self->{_total_count}  // 0 ;
my $sc  = scalar keys %{$self->{local_selected}} ;
my $status ;

if (ref $self->{status_format} eq 'CODE')
	{
	$status = $self->{status_format}->($mc, $tc, $sc) ;
	}
elsif (defined $self->{status_format})
	{
	$status = sprintf($self->{status_format}, $mc, $tc, $sc) ;
	}
else
	{
	$status = msg(MSG_MATCH_COUNT, $mc, $tc) ;
	$status .= "  [$sc selected]" if $self->{multi} ;
	}

$self->{status_label}->set_text($status) ;
}

# ------------------------------------------------------------------------------

sub _maybe_fire_selection_change
{
my ($self, $old_sel, $changed_idx, $new_state, $changed_text) = @_ ;

return unless $self->{on_selection_change} ;

my %new_sel = %{$self->{local_selected}} ;
my $changed = (keys %new_sel != keys %$old_sel) ;

unless ($changed)
	{
	for my $k (keys %new_sel)
		{
		$changed = 1, last unless $old_sel->{$k} ;
		}
	}

return unless $changed ;

my @sel = map { [$self->{_all_items}[$_] // '', $_] }
	grep { $self->{local_selected}{$_} }
	@{$self->{_match_indices}} ;

# Callback receives:
#   $widget, $selections, $changed_idx, $selected_state, $changed_text
# $changed_idx    — original index of the item that was toggled
# $selected_state — 1 if item was just selected, 0 if deselected
# $changed_text   — text of the toggled item
$self->{on_selection_change}->(
	$self,
	\@sel,
	$changed_idx // undef,
	$new_state   // undef,
	$changed_text // undef,
	) ;
}

# ------------------------------------------------------------------------------

sub _get_positions
{
my ($self, $text, $query) = @_ ;

return [] unless length($query) ;

# Use user-supplied position function if provided
return $self->{position_fn}->($text, $query) if $self->{position_fn} ;

return _fuzzy_positions($text, $query) ;
}

# ------------------------------------------------------------------------------

sub _fuzzy_positions
{
my ($text, $query) = @_ ;

# Find the leftmost subsequence match of query characters in text.
# Each query character must appear in order in text (case-insensitive).
# Returns arrayref of matching character indices in text, or [] if no match.
#
# fzf does not return match positions in its HTTP response.
# This implementation mirrors fzf's basic fuzzy matching logic.
# Issue filed: https://github.com/junegunn/fzf/issues/XXXX

my $lc_text  = lc($text) ;
my $lc_query = lc($query) ;
my @positions ;
my $ti = 0 ;

for my $qi (0 .. length($lc_query) - 1)
	{
	my $qc  = substr($lc_query, $qi, 1) ;
	my $idx = index($lc_text, $qc, $ti) ;

	return [] if $idx < 0 ;

	push @positions, $idx ;
	$ti = $idx + 1 ;
	}

return \@positions ;
}

# ------------------------------------------------------------------------------

my %ANSI_FG =
	(
	30 => '#000000', 31 => '#cc0000', 32 => '#4e9a06', 33 => '#c4a000',
	34 => '#3465a4', 35 => '#75507b', 36 => '#06989a', 37 => '#d3d7cf',
	90 => '#555753', 91 => '#ef2929', 92 => '#8ae234', 93 => '#fce94f',
	94 => '#729fcf', 95 => '#ad7fa8', 96 => '#34e2e2', 97 => '#eeeeec',
	) ;

my %ANSI_BG =
	(
	40 => '#000000', 41 => '#cc0000', 42 => '#4e9a06', 43 => '#c4a000',
	44 => '#3465a4', 45 => '#75507b', 46 => '#06989a', 47 => '#d3d7cf',
	100 => '#555753', 101 => '#ef2929', 102 => '#8ae234', 103 => '#fce94f',
	104 => '#729fcf', 105 => '#ad7fa8', 106 => '#34e2e2', 107 => '#eeeeec',
	) ;

# Convert a 256-colour palette index to a CSS hex color string.
# 0-7:    standard colours (matches ANSI_FG 30-37)
# 8-15:   high-intensity colours (matches ANSI_FG 90-97)
# 16-231: 6x6x6 RGB colour cube
# 232-255: greyscale ramp

my @_16_COLORS = (
	'#000000', '#cc0000', '#4e9a06', '#c4a000',
	'#3465a4', '#75507b', '#06989a', '#d3d7cf',
	'#555753', '#ef2929', '#8ae234', '#fce94f',
	'#729fcf', '#ad7fa8', '#34e2e2', '#eeeeec',
	) ;

sub _256_color
{
my ($n) = @_ ;

$n //= 0 ;
$n  = 0 if $n < 0 ;
$n  = 255 if $n > 255 ;

return $_16_COLORS[$n] if $n < 16 ;

if ($n < 232)
	{
	my $i = $n - 16 ;
	my $b = $i % 6 ;
	my $g = int($i / 6)  % 6 ;
	my $r = int($i / 36) % 6 ;
	my @v = (0, 95, 135, 175, 215, 255) ;

	return sprintf('#%02x%02x%02x', $v[$r], $v[$g], $v[$b]) ;
	}

# Greyscale 232-255
my $level = 8 + ($n - 232) * 10 ;

return sprintf('#%02x%02x%02x', $level, $level, $level) ;
}

sub _ansi_to_markup
{
my ($self, $text, $hit_pos, $match_fg, $match_bg) = @_ ;

$hit_pos  //= {} ;
$match_fg //= '' ;
$match_bg //= undef ;

my $markup    = '' ;
my $cur_fg    = undef ;
my $cur_bg    = undef ;
my $bold      = 0 ;
my $pos       = 0 ;
my $len       = length($text) ;
my $vis_index = 0 ;

while ($pos < $len)
	{
	if (substr($text, $pos, 1) eq "\x1b"
		&& $pos + 1 < $len
		&& substr($text, $pos + 1, 1) eq '[')
		{
		my $end = index($text, 'm', $pos + 2) ;
		last if $end == -1 ;

		my $codes_str = substr($text, $pos + 2, $end - $pos - 2) ;
		$pos          = $end + 1 ;

		my @codes = map { $_ + 0 } split(/;/, $codes_str || '0') ;
		my $ci    = 0 ;

		while ($ci < @codes)
			{
			my $code = $codes[$ci++] ;

			if ($code == 0)
				{
				$cur_fg = undef ; $cur_bg = undef ; $bold = 0 ;
				}
			elsif ($code == 1)  { $bold = 1 }
			elsif ($code == 22) { $bold = 0 }
			elsif ($code == 38 && $codes[$ci] == 5 && defined $codes[$ci + 1])
				{
				# 256-colour foreground: 38;5;N
				$ci++ ;
				$cur_fg = _256_color($codes[$ci++]) ;
				}
			elsif ($code == 48 && $codes[$ci] == 5 && defined $codes[$ci + 1])
				{
				# 256-colour background: 48;5;N
				$ci++ ;
				$cur_bg = _256_color($codes[$ci++]) ;
				}
			elsif ($code == 38 && $codes[$ci] == 2
				&& defined $codes[$ci+1] && defined $codes[$ci+2])
				{
				# Truecolour foreground: 38;2;R;G;B
				$ci++ ;
				my ($r, $g, $b) = @codes[$ci .. $ci+2] ;
				$cur_fg = sprintf('#%02x%02x%02x', $r, $g, $b) ;
				$ci += 3 ;
				}
			elsif ($code == 48 && $codes[$ci] == 2
				&& defined $codes[$ci+1] && defined $codes[$ci+2])
				{
				# Truecolour background: 48;2;R;G;B
				$ci++ ;
				my ($r, $g, $b) = @codes[$ci .. $ci+2] ;
				$cur_bg = sprintf('#%02x%02x%02x', $r, $g, $b) ;
				$ci += 3 ;
				}
			elsif (exists $ANSI_FG{$code}) { $cur_fg = $ANSI_FG{$code} }
			elsif (exists $ANSI_BG{$code}) { $cur_bg = $ANSI_BG{$code} }
			}
		}
	else
		{
		my $ch      = _escape_markup(substr($text, $pos, 1)) ;
		my $is_hit  = $hit_pos->{$vis_index} ;
		$pos++ ;
		$vis_index++ ;

		my $span_fg = $is_hit && $match_fg ? $match_fg : $cur_fg ;
		my $span_bg = $is_hit && $match_bg ? $match_bg : $cur_bg ;

		# When bold is active, map standard foreground colors (30-37)
		# to their bright equivalents (90-97) — matches how modern
		# terminals render bold text (bold-is-bright behaviour).
		if ($bold && !$is_hit && defined $span_fg)
			{
			my %bright_map =
				(
				'#000000' => '#555753',
				'#cc0000' => '#ef2929',
				'#4e9a06' => '#8ae234',
				'#c4a000' => '#fce94f',
				'#3465a4' => '#729fcf',
				'#75507b' => '#ad7fa8',
				'#06989a' => '#34e2e2',
				'#d3d7cf' => '#eeeeec',
				) ;
			$span_fg = $bright_map{$span_fg} // $span_fg ;
			}

		if ($span_fg || $span_bg || $bold)
			{
			my $span = '<span' ;
			$span   .= " foreground=\"$span_fg\""  if $span_fg ;
			$span   .= " background=\"$span_bg\""  if $span_bg ;
			$span   .= ' weight="bold"'             if $bold ;
			$span   .= ">$ch</span>" ;
			$markup .= $span ;
			}
		else
			{
			$markup .= $ch ;
			}
		}
	}

return $markup ;
}

# ------------------------------------------------------------------------------

sub _make_markup
{
my ($self, $text, $positions, $is_cursor, $stripe_bg, $ansi_src) = @_ ;

my $c  = $self->{colors} ;

# Note: transform_fn is applied by the caller before calling _make_markup.
# Do NOT apply it again here.

if ($self->{ansi})
	{
	# $ansi_src is the original item text with ANSI codes intact.
	# $positions are indices into the plain (stripped) display text.
	# $text is the plain display text used to compute positions.
	my $src    = defined $ansi_src ? $ansi_src : $text ;
	my %hit    = map { $_ => 1 } @{$positions // []} ;
	my $markup = $self->_ansi_to_markup($src, \%hit, $c->{match_fg}, $c->{match_bg}) ;

	return $markup ;
	}

# Tab expansion with position remapping
my $tw       = $self->{tab_width} // 8 ;
my $col      = 0 ;
my $expanded = '' ;
my %pos_map ;

for my $i (0 .. length($text) - 1)
	{
	$pos_map{$i} = length($expanded) ;
	my $ch = substr($text, $i, 1) ;

	if ($ch eq "\t")
		{
		my $spaces = $tw - ($col % $tw) ;
		$expanded .= ' ' x $spaces ;
		$col      += $spaces ;
		}
	else
		{
		$expanded .= $ch ;
		$col++ ;
		}
	}

$text = $expanded ;

my @mapped_pos = map { $pos_map{$_} // () } @{$positions // []} ;
my $escaped    = _escape_markup($text) ;
my $wfg        = $is_cursor ? ($c->{cursor_fg} // '#ffffff') : $c->{widget_fg} ;
my $fg         = $c->{match_fg} ;
my $bg         = $c->{match_bg} ;

my $markup ;

if (!$self->{highlight} || !@mapped_pos)
	{
	$markup = $wfg ? "<span foreground=\"$wfg\">$escaped</span>" : $escaped ;
	}
else
	{
	my %pos = map { $_ => 1 } @mapped_pos ;
	$markup  = '' ;

	for my $i (0 .. length($text) - 1)
		{
		my $char = _escape_markup(substr($text, $i, 1)) ;

		if ($pos{$i})
			{
			my $span  = "<span foreground=\"$fg\"" ;
			$span    .= " background=\"$bg\"" if $bg ;
			$span    .= ">$char</span>" ;
			$markup  .= $span ;
			}
		elsif ($wfg)
			{
			$markup .= "<span foreground=\"$wfg\">$char</span>" ;
			}
		else
			{
			$markup .= $char ;
			}
		}
	}

return $markup ;
}

# ------------------------------------------------------------------------------

sub _escape_markup
{
my ($text) = @_ ;
$text =~ s/&/&amp;/g ;
$text =~ s/</&lt;/g ;
$text =~ s/>/&gt;/g ;
return $text ;
}

# ------------------------------------------------------------------------------

sub _apply_theme
{
my ($self, $theme_name) = @_ ;

my $theme = $THEMES{$theme_name} or return ;

$self->{_theme_name} = $theme_name ;

my $uc = $self->{_user_colors} // {} ;
$self->{colors} =
	{
	widget_fg            => $uc->{widget_fg}            // $theme->{widget_fg},
	widget_bg            => $uc->{widget_bg}            // $theme->{widget_bg},
	entry_fg             => $uc->{entry_fg}             // $theme->{entry_fg},
	entry_bg             => $uc->{entry_bg}             // $theme->{entry_bg},
	match_fg             => $uc->{match_fg}             // $theme->{match_fg},
	match_bg             => $uc->{match_bg}             // $theme->{match_bg},
	checkbox_fg          => $uc->{checkbox_fg}          // $theme->{checkbox_fg},
	checkbox_bg          => $uc->{checkbox_bg}          // $theme->{checkbox_bg},
	checkbox_selected_fg => $uc->{checkbox_selected_fg} // $theme->{checkbox_selected_fg},
	checkbox_selected_bg => $uc->{checkbox_selected_bg} // $theme->{checkbox_selected_bg},
	cursor_fg            => $uc->{cursor_fg}            // $theme->{cursor_fg},
	cursor_bg            => $uc->{cursor_bg}            // $theme->{cursor_bg},
	border_color         => $uc->{border_color}         // $theme->{border_color},
	header_fg            => $uc->{header_fg}            // $theme->{header_fg},
	header_bg            => $uc->{header_bg}            // $theme->{header_bg},
	info_fg              => $uc->{info_fg}              // $theme->{info_fg},
	info_bg              => $uc->{info_bg}              // $theme->{info_bg},
	} ;

my $c       = $self->{colors} ;
my $tv_name = $self->{tree_view}->get_name() ;
my $wb_name = $self->{widget_box}->get_name() ;
my $bb_name = $self->{bottom_bar} ? $self->{bottom_bar}->get_name() : '' ;
my $sl_name = $self->{status_label}->get_name() ;

my @css ;

	{
	my @p ;
	push @p, "color: $c->{entry_fg}"            if $c->{entry_fg} ;
	push @p, "background-color: $c->{entry_bg}" if $c->{entry_bg} ;
	push @p, "font-family: $self->{font_family}" if $self->{font_family} ;
	push @p, "font-size: $self->{font_size}pt"   if $self->{font_size} ;
	my $caret = $c->{entry_fg} // '#000000' ;
	push @p, "caret-color: $caret" ;
	push @css, "entry { " . join(' ; ', @p) . " }" ;
	}

if ($c->{widget_bg} || $c->{widget_fg})
	{
	my @p ;
	push @p, "color: $c->{widget_fg}"            if $c->{widget_fg} ;
	push @p, "background-color: $c->{widget_bg}" if $c->{widget_bg} ;
	push @css, "#$tv_name { " . join(' ; ', @p) . " }" ;
	}

push @css, "#$tv_name cell { padding-top: $self->{row_spacing}px ; padding-bottom: $self->{row_spacing}px }" ;
push @css, "#$wb_name { background-color: $c->{widget_bg} }"                           if $c->{widget_bg} ;
push @css, "#$bb_name { background-color: $c->{widget_bg} ; margin: 0 ; padding: 0 }" if $bb_name && $c->{widget_bg} ;
push @css, "#$sl_name { color: $c->{widget_fg} }"                                      if $c->{widget_fg} ;

if (@css)
	{
	my $screen   = Gtk3::Gdk::Screen::get_default() ;
	my $priority = Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION ;

	if ($self->{_css_provider})
		{
		Gtk3::StyleContext::remove_provider_for_screen($screen, $self->{_css_provider}) ;
		}

	my $provider = Gtk3::CssProvider->new() ;
	$provider->load_from_data(join("\n", @css)) ;
	Gtk3::StyleContext::add_provider_for_screen($screen, $provider, $priority) ;
	$self->{_css_provider} = $provider ;
	}

# Force redraw of all visible rows with new colors
$self->_rebuild_store() ;
}

# ------------------------------------------------------------------------------

sub _on_process_error
{
my ($self, $error_msg) = @_ ;

$self->_show_error($error_msg) ;
$self->{on_error}->($self, $error_msg) if $self->{on_error} ;
}

# ------------------------------------------------------------------------------

sub _set_loading
{
my ($self, $loading) = @_ ;

$self->{loading} = $loading ;
$self->{scroll_win}->set_sensitive(!$loading) ;
$self->{ok_button}->set_sensitive(!$loading) if $self->{show_buttons} ;
$self->{status_label}->set_text(msg(MSG_LOADING)) if $loading && $self->{show_status} ;
}

# ------------------------------------------------------------------------------

sub _show_error
{
my ($self, $error_msg) = @_ ;

$self->_stop_load_timer() ;
$self->{error_label}->set_text($error_msg) ;
$self->{widget_box}->hide() ;
$self->{error_label}->show() ;
}

# ------------------------------------------------------------------------------

sub _cleanup
{
my ($self) = @_ ;

$self->_stop_load_timer() ;
$self->_stop_query_refresh_timer() ;

if ($self->{debounce_timer})
	{
	Glib::Source->remove($self->{debounce_timer}) ;
	$self->{debounce_timer} = undef ;
	}

# SocketBackend::stop() also stops the process; call process->stop()
# only if there is no backend (e.g. before fzf connected).
if ($self->{_backend})
	{
	$self->{_backend}->stop() ;
	$self->{_backend} = undef ;
	}
elsif ($self->{process})
	{
	$self->{process}->stop() ;
	}

$self->{process} = undef ;
}

# ------------------------------------------------------------------------------
# Public methods

sub set_items
{
my ($self, $items, $query) = @_ ;

$self->_stop_load_timer() ;
$self->_stop_query_refresh_timer() ;
$self->{_backend}         = undef ;
$self->{_match_indices}   = [] ;
$self->{_match_count}     = 0 ;
$self->{_total_count}     = 0 ;
$self->{_fetch_in_flight} = 0 ;
$self->{_prefetch_at}     = 0 ;
$self->{local_pos}        = 0 ;
$self->{local_selected}   = {} ;
$self->{last_query}       = undef ;
$self->{query_buffer}     = undef ;

my $effective_query = defined $query ? $query : $self->{entry}->get_text() ;
$self->{entry}->set_text($effective_query) if defined $query ;

unless ($self->{process})
	{
	$self->_start_fzf($items) ;
	return ;
	}

$self->{process}->{items}    = $items ;
$self->{process}->{on_ready} = sub { $self->_on_process_ready() } ;
$self->{process}->set_items($items, $effective_query) ;
}

# ------------------------------------------------------------------------------

sub _drain_iterator
{
my ($iter) = @_ ;
my @all ;
while (defined(my $batch = $iter->()))
	{
	my @items = ref $batch ? @$batch : ($batch) ;
	for my $item (@items)
		{
		$item = decode_utf8($item) if defined $item && !is_utf8($item) ;
		}
	push @all, @items ;
	}
return \@all ;
}

# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------

sub _start_fzf
{
my ($self, $items) = @_ ;

$self->_set_loading(1) ;

my ($ok, $msg_or_ver) = Gtk3::FzfWidget::Process->check_fzf_version() ;

unless ($ok)
	{
	$self->_show_error($msg_or_ver) ;
	return ;
	}

# For plain arrayrefs: store directly.
# For coderefs: pass to ItemWriter as-is (it handles coderefs natively in
# a forked child).  Populate _all_items from the same array so text lookup
# works; for coderefs we populate lazily after widget is shown.
my $item_list = ref $items eq 'CODE' ? [] : $items ;
$self->{_all_items}   = $item_list ;
$self->{_items_src}   = $items ;   # original source (arrayref or coderef)

my @extra_opts ;
push @extra_opts, '--exact'  if ($self->{search_mode} // '') eq 'exact' ;
push @extra_opts, '--prefix' if ($self->{search_mode} // '') eq 'prefix' ;

$self->{process} = Gtk3::FzfWidget::Process->new(
	items  => $self->{_items_src},
	config =>
		{
		fzf_opts       => [@{$self->{fzf_opts}}, @extra_opts],
		ansi           => $self->{ansi},
		multi          => $self->{multi},
		start_delay_ms => $self->{start_delay_ms},
		port           => $self->{port},
		},
	on_ready => sub { $self->_on_process_ready() },
	on_error => sub { $self->_on_process_error($_[0]) },
	) ;

$self->{process}->start($self->{initial_query}) ;
}

# ------------------------------------------------------------------------------

sub _on_process_ready
{
my ($self) = @_ ;

$self->_set_loading(0) ;

$self->{_backend} = Gtk3::FzfWidget::SocketBackend->new(
	process => $self->{process},
	) ;

$self->_dbg("process_ready: SocketBackend created") ;

my $query = defined $self->{query_buffer}
	? $self->{query_buffer}
	: ($self->{initial_query} ne '' ? $self->{initial_query} : '') ;

$self->{query_buffer} = undef ;

if ($query ne '')
	{
	$self->{entry}->set_text($query) ;
	}

# Item text arrives from fzf HTTP responses and is cached into _all_items
# as matches come in. No pre-drain needed.
$self->_query_backend($query) ;

if (@{$self->{initial_selection}})
	{
	Glib::Timeout->add(
		$self->{start_delay_ms},
		sub { $self->_apply_initial_selection() ; return 0 },
		) ;
	}

$self->_start_load_timer() ;
$self->{entry}->grab_focus() ;
$self->{entry}->set_position(-1) ;
$self->{on_ready}->($self) if $self->{on_ready} ;
}

# ------------------------------------------------------------------------------

sub reload_items
{
my ($self, $items) = @_ ;

$items //= $self->{process}{items} ;
$self->set_items($items, $self->{entry}->get_text()) ;
}

# ------------------------------------------------------------------------------

sub set_query
{
my ($self, $text) = @_ ;

$self->{entry}->set_text($text // '') ;
}

# ------------------------------------------------------------------------------

sub freeze
{
my ($self) = @_ ;

$self->{frozen} = 1 ;
$self->_stop_load_timer() ;
}

# ------------------------------------------------------------------------------

sub unfreeze
{
my ($self) = @_ ;

$self->{frozen} = 0 ;
$self->_query_backend($self->{entry}->get_text()) ;
}

# ------------------------------------------------------------------------------

sub set_poll_interval
{
my ($self, $ms) = @_ ;
$self->{poll_ms} = $ms ;
}

# ------------------------------------------------------------------------------

sub get_match_count  { $_[0]->{_match_count} // 0 }
sub get_total_count  { $_[0]->{_total_count} // 0 }
sub get_query        { $_[0]->{entry}->get_text() }
sub query_widget     { $_[0]->{entry} }
sub list_widget      { $_[0]->{scroll_win} }
sub status_widget    { $_[0]->{status_label} }
sub header_widget    { $_[0]->{header_label} }
sub info_widget      { $_[0]->{info_label} }

sub set_placeholder_text { $_[0]->{entry}->set_placeholder_text($_[1]) }

# ------------------------------------------------------------------------------

sub get_selection
{
my ($self) = @_ ;

return [] unless @{$self->{_match_indices}} ;

if ($self->{multi} && %{$self->{local_selected}})
	{
	return [
		map  { [$self->{_all_items}[$_] // '', $_] }
		grep { $self->{local_selected}{$_} }
		@{$self->{_match_indices}}
		] ;
	}

my $orig_idx = $self->{_match_indices}[$self->{local_pos}] ;
return [] unless defined $orig_idx ;
return [[$self->{_all_items}[$orig_idx] // '', $orig_idx]] ;
}

# ------------------------------------------------------------------------------

sub get_filtered_list
{
my ($self) = @_ ;
return [map { [$self->{_all_items}[$_] // '', $_] } @{$self->{_match_indices}}] ;
}

# ------------------------------------------------------------------------------

sub _apply_initial_selection
{
my ($self) = @_ ;

return unless @{$self->{initial_selection}} ;
return unless @{$self->{_match_indices}} ;

for my $target_idx (@{$self->{initial_selection}})
	{
	# Find this original index in the current match window
	for my $filter_row (0 .. $#{$self->{_match_indices}})
		{
		if ($self->{_match_indices}[$filter_row] == $target_idx)
			{
			$self->{local_selected}{$target_idx} = 1 ;

			my $siter = $self->{_row_iters}[$filter_row] ;
			$self->{list_store}->set($siter, 2, 1) if $siter ;
			last ;
			}
		}
	}

$self->_update_status_label() ;
}

# ------------------------------------------------------------------------------

sub _confirm
{
my ($self) = @_ ;

my @sel ;

if ($self->{multi} && %{$self->{local_selected}})
	{
	for my $idx (sort { $a <=> $b } keys %{$self->{local_selected}})
		{
		push @sel, [$self->{_all_items}[$idx] // '', $idx] ;
		}
	}
else
	{
	my $orig_idx = $self->{_match_indices}[$self->{local_pos}] ;
	if (defined $orig_idx)
		{
		@sel = ([$self->{_all_items}[$orig_idx] // '', $orig_idx]) ;
		}
	}

$self->{on_confirm}->($self, \@sel, $self->{entry}->get_text()) if $self->{on_confirm} ;

return unless $self->{_backend} ;

if ($self->{persistent})
	{
	$self->{entry}->set_text('') ;
	$self->{local_selected} = {} ;
	$self->_send_query() ;
	}
else
	{
	$self->_cleanup() ;
	}
}

# ------------------------------------------------------------------------------

sub _cancel
{
my ($self) = @_ ;

$self->{on_cancel}->($self) if $self->{on_cancel} ;

my $win = $self->get_toplevel() ;
$win->destroy() if $win && $win->isa('Gtk3::Window') ;
}

# ------------------------------------------------------------------------------

sub _toggle_multi
{
my ($self) = @_ ;

$self->{multi}          = $self->{multi} ? 0 : 1 ;
$self->{local_selected} = {} ;

$self->{_toggle_col}->set_visible($self->{multi}) if $self->{_toggle_col} ;

# Rebuild markup to clear any selection highlighting
$self->_rebuild_store() ;
$self->_update_status_label() ;
}

# ------------------------------------------------------------------------------

my @_THEME_ORDER = qw(normal dark solarized-dark solarized-light) ;

sub _cycle_theme
{
my ($self) = @_ ;

my $current = $self->{_theme_name} // 'normal' ;
my $idx     = 0 ;

for my $i (0 .. $#_THEME_ORDER)
	{
	if ($_THEME_ORDER[$i] eq $current)
		{
		$idx = $i ;
		last ;
		}
	}

my $next = $_THEME_ORDER[($idx + 1) % scalar @_THEME_ORDER] ;
$self->_apply_theme($next) ;
}

1 ;
