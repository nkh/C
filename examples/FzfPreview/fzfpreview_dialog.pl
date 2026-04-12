#!/usr/bin/perl

# Example: GTK window with a button that opens an FzfPreview dialog.
#
# Demonstrates:
#   - Gtk3::FzfPreview embedded inside a Gtk3::Dialog
#   - The dialog closes on confirm or cancel
#   - Selected files are printed in the main window's text view
#   - The preview pane shows the content of each item as it is highlighted
#   - A drag handle between the two panes (resizable => 1)
#
# Run: perl fzfpreview_dialog.pl [directory]

use strict ;
use warnings ;
use lib '../../lib' ;
use Gtk3 -init ;
use Gtk3::FzfPreview ;
use File::Basename qw(basename) ;

Gtk3->init() ;

my $dir = $ARGV[0] // '.' ;

opendir(my $dh, $dir) or die "Cannot open $dir: $!" ;
my @files = sort
	grep { -f "$dir/$_" || -d "$dir/$_" }
	grep { !/^\.\.$/ }
	readdir($dh) ;
closedir($dh) ;

@files = map { "$dir/$_" } @files ;

# ---- Main window -------------------------------------------------------------

my $main_win = Gtk3::Window->new('toplevel') ;
$main_win->set_title('Main application') ;
$main_win->set_default_size(600, 400) ;
$main_win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $main_box    = Gtk3::Box->new('vertical', 8) ;
my $open_button = Gtk3::Button->new_with_label('Open file picker') ;
my $output_buf  = Gtk3::TextBuffer->new() ;
my $output_view = Gtk3::TextView->new_with_buffer($output_buf) ;
$output_view->set_editable(0) ;

my $output_scroll = Gtk3::ScrolledWindow->new(undef, undef) ;
$output_scroll->set_policy('automatic', 'automatic') ;
$output_scroll->add($output_view) ;

$main_box->pack_start($open_button,    0, 0, 4) ;
$main_box->pack_start($output_scroll,  1, 1, 4) ;
$main_win->add($main_box) ;

# ---- Button handler: open dialog with FzfPreview ----------------------------

$open_button->signal_connect(clicked => sub
	{
	my $dialog = Gtk3::Dialog->new_with_buttons(
		'Select files',
		$main_win,
		[qw(modal destroy-with-parent)],
		) ;

	$dialog->set_default_size(900, 600) ;

	# Create the FzfPreview widget
	my $fp = Gtk3::FzfPreview->new(
		items => \@files,

		# item_to_file: the item text is already a full path
		item_to_file => sub { $_[0] },

		config =>
			{
			# Drag handle between fzf list and preview pane
			resizable => 1,

			# fzf pane takes 35% of width; preview takes 65%
			fzf_width => 0.35,

			# Ctrl+H hides/shows the fzf list
			hide_fzf_key => 'ctrl+h',

			# Ctrl+P hides/shows the preview
			hide_preview_key => 'ctrl+p',

			# FzfWidget config
			fzf =>
				{
				theme       => 'dark',
				font_family => 'Monospace',
				font_size   => 12,
				multi       => 1,
				transform_fn => sub { basename($_[0]) },
				},

			# PreviewPane config
			preview =>
				{
				theme    => 'dark',
				fit_mode => 'both',
				},

			# on_preview fires before each preview load.
			# Return ($path, $extra_text) — extra_text shown above/below the content.
			on_preview => sub
				{
				my ($self, $path, $text, $idx) = @_ ;
				my @st      = stat($path) ;
				my $extra   = @st ? sprintf("%s  %d bytes", $path, $st[7]) : $path ;
				return ($path, $extra) ;
				},

			on_confirm => sub
				{
				my ($fp, $sel, $query) = @_ ;
				my $text = join("\n", map { $_->[0] } @$sel) . "\n" ;
				$output_buf->insert($output_buf->get_end_iter(), $text) ;
				$dialog->destroy() ;
				},
			on_cancel => sub { $dialog->destroy() },
			},
		) ;

	my $content = $dialog->get_content_area() ;
	$content->set_spacing(0) ;
	$fp->set_vexpand(1) ;
	$content->pack_start($fp, 1, 1, 0) ;
	$dialog->show_all() ;
	$dialog->run() ;
	} ) ;

$main_win->show_all() ;
Gtk3->main() ;
