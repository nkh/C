#!/usr/bin/perl

# Example: FzfPreview as the sole content of a top-level window.
#
# Demonstrates:
#   - Gtk3::FzfPreview filling an entire window
#   - Resizable split between fzf list and preview pane
#   - persistent => 1: widget stays active after confirm so the user
#     can keep selecting files
#   - Preview loads automatically on startup and on cursor movement
#   - on_confirm prints selected files without quitting
#
# Run: perl fzfpreview_modal.pl [directory]

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

# ---- Window ------------------------------------------------------------------

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('FzfPreview') ;
$win->set_default_size(1000, 650) ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

# Declare $fp before the assignment so it can be referenced inside callbacks.
my $fp ;

$fp = Gtk3::FzfPreview->new(
	items        => \@files,
	item_to_file => sub { $_[0] },

	config =>
		{
		resizable        => 1,
		fzf_width        => 0.35,
		hide_fzf_key     => 'ctrl+h',
		hide_preview_key => 'ctrl+p',

		fzf =>
			{
			theme        => 'dark',
			font_family  => 'Monospace',
			font_size    => 12,
			show_buttons => 0,
			persistent   => 1,
			transform_fn => sub { basename($_[0]) },
			on_ready     => sub
				{
				my ($w) = @_ ;
				my $sel = $w->get_selection() ;
				$fp->preview_item($sel->[0][0], $sel->[0][1])
					if $fp && $sel && @$sel ;
				},
			},

		preview =>
			{
			theme    => 'dark',
			fit_mode => 'both',
			},

		on_preview => sub
			{
			my ($self, $path, $text, $idx) = @_ ;
			my @st    = stat($path) ;
			my $extra = @st ? sprintf("%s  %d bytes", $path, $st[7]) : $path ;
			return ($path, $extra) ;
			},

		on_confirm => sub
			{
			my ($fp, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			},
		on_cancel => sub { Gtk3->main_quit() },
		},
	) ;

$fp->set_vexpand(1) ;
$fp->set_hexpand(1) ;
$win->add($fp) ;
$win->show_all() ;
Gtk3->main() ;
