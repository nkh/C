#!/usr/bin/perl

# Example 00 — Complete configuration reference.
#
# Every available option is listed here, set to an explicit value, with a
# comment explaining its type, default, and purpose. Use this file as an
# inline reference manual when building a new widget.
#
# All options have sensible defaults. Remove any key you do not need.
#
# Run:   perl 00_all_options_template.pl
# Items are read from stdin when it is not a terminal, otherwise a built-in
# list is used.

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

# ---- Items ---------------------------------------------------------------
# items: arrayref of strings, or a coderef returning one.
# The coderef form defers item generation until the widget starts.

my @items ;

if (!-t STDIN)
	{
	chomp(@items = <STDIN>) ;
	}
else
	{
	@items = map { sprintf('item %02d — sample text', $_) } 1 .. 40 ;
	}

# ---- Window --------------------------------------------------------------

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('00 - all options reference') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

# ---- Widget --------------------------------------------------------------

my $widget = Gtk3::FzfWidget->new(

	# items: arrayref of strings | coderef returning arrayref of strings
	# The coderef is called once at startup.
	items => \@items,

	# layout: arrayref — vertical order of UI slots inside the widget.
	# Valid slots: 'query', 'list', 'header' (header requires header => '...' in config).
	# Default: [qw(query list)] or [qw(header query list)] when header is set.
	layout => [qw(header query list)],

	config =>
		{
		# ------------------------------------------------------------------
		# Search and behaviour
		# ------------------------------------------------------------------

		# fzf_opts: arrayref of strings — extra flags passed verbatim to fzf.
		# Options conflicting with headless mode (--height, --tmux, --tty,
		# --no-tty) are rejected with a warning. Default: []
		fzf_opts          => ['--no-sort', '--tiebreak=index'],

		# search_mode: string — fzf matching algorithm.
		# 'fuzzy'  — standard subsequence matching (default).
		# 'exact'  — substring must match literally (fzf --exact).
		# 'prefix' — query must match at the start of each item (fzf --prefix).
		# Default: 'fuzzy'
		search_mode       => 'fuzzy',

		# ansi: bool — render ANSI SGR escape codes in item text as colors.
		# Set to 1 when items contain \e[31m....\e[0m style sequences.
		# Default: 0
		ansi              => 0,

		# highlight: bool — highlight matched character positions in match_fg.
		# Set to 0 to disable all match highlighting.
		# Default: 1
		highlight         => 1,

		# multi: bool — enable multi-select mode.
		# Shows a checkbox column. Tab or click toggles individual rows.
		# Ctrl+A / Ctrl+D select and deselect all visible rows.
		# Default: 0
		multi             => 1,

		# wrap_cursor: bool — cursor wraps at list top and bottom.
		# Default: 0
		wrap_cursor       => 0,

		# page_step: integer | undef — rows moved by Page Up / Page Down.
		# undef = number of currently visible rows minus 1, so the last
		# visible row becomes the first after Page Down. A fixed integer
		# overrides this. Default: undef
		page_step         => undef,

		# initial_query: string — text pre-filled in the search entry at startup.
		# Default: ''
		initial_query     => '',

		# initial_selection: arrayref of integers — original item indices to
		# pre-check at startup. Only meaningful in multi mode.
		# Default: []
		initial_selection => [0, 2, 4],

		# ------------------------------------------------------------------
		# Timing and network
		# ------------------------------------------------------------------

		# poll_ms: integer — background poll interval in milliseconds.
		# A refresh is triggered only when match count or total count changes.
		# Lower values are more responsive but use more CPU.
		# Default: 1000
		poll_ms           => 1000,

		# start_delay_ms: integer — ms to wait after spawning fzf before
		# connecting to its HTTP port. Increase on slow machines.
		# Default: 100
		start_delay_ms    => 100,

		# port: integer | undef — TCP port for fzf --listen.
		# undef lets the OS assign a free port automatically.
		# Default: undef
		port              => undef,

		# debounce_table: arrayref of [$threshold, $ms] pairs | undef.
		# Controls how long to wait after the last keystroke before sending
		# the query to fzf. Evaluated top to bottom; first matching pair wins.
		# $threshold is the max total item count for that row; undef matches any.
		# undef uses the built-in table below.
		# Default: undef
		#   built-in: [[500,30],[2000,100],[10000,200],[100000,350],[undef,500]]
		debounce_table    =>
			[
			[    500,  30],
			[   2000, 100],
			[  10000, 200],
			[ 100000, 350],
			[  undef, 500],
			],

		# lazy_fetch_initial: integer — rows fetched from fzf immediately after
		# a query change. Only this many rows are transferred over HTTP before
		# the widget becomes responsive. Further rows are fetched on demand as
		# the user scrolls toward the end of what is loaded.
		# Reduce for very slow connections; increase if you want more rows
		# available before scrolling begins.
		# Default: 300
		lazy_fetch_initial   => 300,

		# lazy_fetch_page: integer — additional rows fetched from fzf each time
		# the user scrolls close to the end of the loaded window.
		# Default: 100
		lazy_fetch_page      => 100,

		# lazy_fetch_threshold: integer — how many rows before the bottom of the
		# loaded window triggers the next page fetch. When the cursor is within
		# this many rows of the last loaded row, the next page is prefetched.
		# Set to 0 to fetch only when the cursor reaches the very last row.
		# Default: 50
		lazy_fetch_threshold => 50,

		# ------------------------------------------------------------------
		# Window geometry
		# ------------------------------------------------------------------

		# width: integer | 'half_screen' | 'full_screen'
		# Requested window width in pixels. Clamped to screen width.
		# Default: 'half_screen'
		width             => 'half_screen',

		# height: integer | 'full_screen'
		# Requested window height in pixels. Clamped to screen height.
		# Default: 'full_screen'
		height            => 'full_screen',

		# min_height: integer | undef — minimum window height in pixels.
		# Prevents height from being smaller than this value.
		# Default: undef
		min_height        => undef,

		# max_height: integer | 'screen' | undef — maximum window height.
		# 'screen' means the full screen height.
		# Default: 'screen'
		max_height        => 'screen',

		# border_width: integer — padding in pixels between the window edge
		# and the widget content. The window background shows through as the
		# visible border. Works with colors => { border_color => ... }.
		# Default: 2
		border_width      => 4,

		# ------------------------------------------------------------------
		# Typography
		# ------------------------------------------------------------------

		# font_family: string — font family for the list rows and search entry.
		# Default: 'Monospace'
		font_family        => 'Monospace',

		# font_size: integer — font size in points for list rows and entry.
		# Default: 15
		font_size          => 14,

		# tab_width: integer — number of spaces a tab character expands to.
		# Used to remap fuzzy match highlight positions after expansion.
		# Default: 8
		tab_width          => 8,

		# ------------------------------------------------------------------
		# Header
		# ------------------------------------------------------------------

		# header: string | undef — static label displayed in the header slot.
		# When set the header slot is added to the layout automatically.
		# Default: undef
		header             => 'Name       Type    Size',

		# header_font_family: string | undef — font family for the header label.
		# Should match font_family for column alignment across header and rows.
		# Default: undef
		header_font_family => 'Monospace',

		# header_font_size: integer | undef — font size for the header in points.
		# Should match font_size for column alignment.
		# Default: undef
		header_font_size   => 14,

		# ------------------------------------------------------------------
		# Status bar
		# ------------------------------------------------------------------

		# show_buttons: bool — show the OK and Close buttons.
		# Default: 1
		show_buttons      => 1,

		# show_status: bool — show the match/total counter in the bottom bar.
		# Default: 1
		show_status       => 1,

		# status_format: string | coderef | undef
		# string:  sprintf format receiving ($match_count, $total_count, $selected_count).
		# coderef: called as $fn->($match_count, $total_count, $selected_count),
		#          must return the string to display.
		# undef:   built-in format "N/M" with selection count appended in multi mode.
		# Default: undef
		status_format     => sub
			{
			my ($mc, $tc, $sc) = @_ ;
			return $sc ? "$mc/$tc  [$sc selected]" : "$mc/$tc" ;
			},

		# ------------------------------------------------------------------
		# List appearance
		# ------------------------------------------------------------------

		# row_striping: arrayref of CSS color strings | undef.
		# Colors cycle across rows: row N uses $colors[N % @colors].
		# The cursor row always uses cursor_bg regardless of striping.
		# Default: undef
		row_striping       => ['#1e1e2e', '#1a2035'],

		# row_spacing: integer — vertical padding in pixels above and below
		# each row. 0 suppresses GTK3's default cell padding entirely.
		# Default: 0
		row_spacing        => 0,

		# image_max_width: integer — maximum thumbnail width in pixels.
		# Only relevant when image_fn is set.
		# Default: 64
		image_max_width    => 64,

		# image_max_height: integer — maximum thumbnail height in pixels.
		# Only relevant when image_fn is set.
		# Default: 64
		image_max_height   => 64,

		# ------------------------------------------------------------------
		# Info area (shown only when on_hover is set)
		# ------------------------------------------------------------------

		# info_height: integer — height in pixels of the hover info area.
		# Default: 60
		info_height        => 60,

		# info_font_family: string | undef — font family for the info area.
		# Default: undef
		info_font_family   => undef,

		# info_font_size: integer | undef — font size for the info area in points.
		# Default: undef
		info_font_size     => undef,

		# ------------------------------------------------------------------
		# Theme and colors
		# ------------------------------------------------------------------

		# theme: string — built-in color theme.
		# One of: 'normal', 'dark', 'solarized-dark', 'solarized-light'.
		# Individual keys in colors => {} override the theme per key.
		# Default: 'normal'
		theme              => 'dark',

		# colors: hashref — per-key color overrides applied on top of the theme.
		# All values are CSS color strings (e.g. '#rrggbb') or undef to inherit
		# from the theme.
		colors =>
			{
			widget_fg            => '#d4d4d4',  # list row text
			widget_bg            => '#1e1e1e',  # list background
			entry_fg             => '#d4d4d4',  # search entry text
			entry_bg             => '#252526',  # search entry background
			match_fg             => '#f39c12',  # matched character foreground
			match_bg             => undef,      # matched character background (undef = transparent)
			cursor_fg            => '#ffffff',  # cursor row text
			cursor_bg            => '#264f78',  # cursor row background
			checkbox_fg          => '#d4d4d4',  # checkbox column text (multi only)
			checkbox_bg          => undef,      # checkbox background
			checkbox_selected_fg => '#ff4444',  # checked checkbox foreground
			checkbox_selected_bg => undef,      # checked checkbox background
			border_color         => '#3c3c3c',  # window background visible as border
			header_fg            => '#cccccc',  # header label text
			header_bg            => '#252526',  # header label background
			info_fg              => '#aaaaaa',  # info area text
			info_bg              => '#252526',  # info area background
			},

		# ------------------------------------------------------------------
		# Keybindings
		# ------------------------------------------------------------------

		# keybindings: hashref — override individual key bindings.
		# Format: 'modifier+key' or 'key'.
		# Modifiers: ctrl, shift.
		# Named keys: return, kp_enter, escape, tab, home, end,
		#             page_up, page_down, up, down.
		# Single ASCII characters are also accepted.
		# Navigation keys (Up/Down/Page Up/Page Down/Ctrl+Home/Ctrl+End)
		# are fixed and cannot be rebound.
		keybindings =>
			{
			confirm      => 'ctrl+o',   # confirm selection — fires on_confirm
			confirm2     => 'return',   # alternate confirm binding
			cancel       => 'escape',   # cancel — fires on_cancel, destroys window
			focus_entry  => 'ctrl+q',   # move keyboard focus to search entry
			clear_query  => 'ctrl+u',   # clear search entry text
			select_all   => 'ctrl+a',   # select all visible rows (multi only)
			deselect_all => 'ctrl+d',   # deselect all rows (multi only)
			toggle       => 'tab',      # toggle cursor row and advance (multi only)
			},

		# ------------------------------------------------------------------
		# Advanced callbacks
		# ------------------------------------------------------------------

		# transform_fn: coderef | undef — ($text) -> $display_text
		# Called for every item before display. The return value replaces the
		# visible text; the original text is still returned by on_confirm.
		# Highlight positions are computed on the transformed text.
		# Default: undef
		transform_fn       => undef,

		# image_fn: coderef | undef — ($text, $original_index) -> $pixbuf | undef
		# Called for every row in the current match list after each refresh.
		# Return a Gtk3::Gdk::Pixbuf or undef. The image column is shown only
		# when at least one row returns a pixbuf.
		# Default: undef
		image_fn           => undef,

		# position_fn: coderef | undef — ($text, $query) -> \@char_indices
		# Override the built-in fuzzy match position highlighter.
		# Return arrayref of zero-based character indices in $text to highlight.
		# Default: undef (uses built-in subsequence algorithm)
		position_fn        => undef,

		# ------------------------------------------------------------------
		# Callbacks
		# ------------------------------------------------------------------

		# on_confirm: coderef — ($widget, $selections, $query)
		#   $selections — arrayref of [$text, $original_index] pairs.
		#                 Single-select: always one element (cursor row).
		#                 Multi-select:  all toggled rows, or cursor row if none toggled.
		#   $query      — search entry text at time of confirm.
		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "query: $query\n" ;
			print "$_->[0] (index $_->[1])\n" for @$sel ;
			Gtk3->main_quit() ;
			},

		# on_cancel: coderef — ($widget)
		#   Called when the user closes without confirming.
		#   The enclosing window is destroyed after the callback returns.
		on_cancel => sub { Gtk3->main_quit() },

		# on_error: coderef — ($widget, $message)
		#   Called when fzf fails to start or crashes after all restarts.
		#   fzf is restarted up to 3 times before this is called.
		on_error => sub
			{
			my ($w, $msg) = @_ ;
			warn "fzf error: $msg\n" ;
			Gtk3->main_quit() ;
			},

		# on_query_change: coderef | undef — ($widget, $query)
		#   Called each time the search text changes, after the debounce delay
		#   and after the new query has been sent to fzf.
		on_query_change => sub
			{
			my ($w, $query) = @_ ;
			# print STDERR "query: $query\n" ;
			},

		# on_selection_change: coderef | undef
		#   ($widget, $selections, $changed_idx, $selected_state, $changed_text)
		#   Called in multi mode each time a row is toggled, and after
		#   Ctrl+A / Ctrl+D bulk operations.
		#   $selections    — arrayref of all currently selected [$text, $index] pairs.
		#   $changed_idx   — original index of the toggled item (undef for bulk ops).
		#   $selected_state — 1 = just selected, 0 = just deselected.
		#   $changed_text  — text of the toggled item (undef for bulk ops).
		on_selection_change => sub
			{
			my ($w, $sel, $idx, $state, $text) = @_ ;
			printf STDERR "%d item(s) selected\n", scalar @$sel ;
			},

		# on_hover: coderef | undef — ($widget, $text, $original_index) -> string
		#   Called when the mouse moves over a row.
		#   The return value is displayed in the info area below the list.
		#   The info area is only shown when this callback is set.
		on_hover => sub
			{
			my ($w, $text, $idx) = @_ ;
			return "index $idx: $text" ;
			},

		# on_ready: coderef | undef — ($widget)
		#   Called once after fzf has started and finished loading all items.
		on_ready => sub
			{
			my ($w) = @_ ;
			# print STDERR "widget ready\n" ;
			},
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
