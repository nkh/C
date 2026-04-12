#!/usr/bin/perl

# Example 36 — --preview where the external process writes to the terminal.
#
# Demonstrates:
#   - A previewer that produces no fzfw output (no TEXT:/IMAGE: line)
#   - The previewer writes directly to /dev/tty so output appears in the
#     terminal that launched fzfw, not in any preview pane
#   - Placeholders: {} {index} {selected} {query} {port} {tmpdir}
#   - {port} gives the previewer direct read access to fzf's HTTP API,
#     which is read-only — do not POST to it from the previewer
#
# Because the previewer produces no output, no --preview-width is passed
# and no pane appears in the window.
#
# Run: perl 36_preview_terminal.pl
#      Watch the terminal for per-cursor diagnostic output.

use strict ;
use warnings ;
use lib '../lib' ;
use FindBin ;
use File::Basename qw(dirname) ;
use Cwd qw(abs_path) ;

my $script = abs_path(dirname(__FILE__)) . '/36_preview_terminal.sh' ;

die "previewer not found: $script\n"      unless -f $script ;
die "previewer not executable: $script\n" unless -x $script ;

my @items = map { sprintf('item %02d — %s', $_, join('', map { ('a'..'z')[rand 26] } 1 .. 6)) } 1 .. 50 ;

# Placeholders:
#   {}        item text (shell-quoted)
#   {index}   original item index
#   {selected} 1 if selected, 0 otherwise
#   {query}   current query (shell-quoted)
#   {port}    fzf HTTP listen port (read-only access to fzf state)
#   {tmpdir}  per-session temp directory

my $preview_spec =
	"$script {} {index} {selected} {query} {port} {tmpdir}" ;

my @cmd =
	(
	'perl', "$FindBin::Bin/../script/fzfw",
	'--theme',   'dark',
	'--multi',
	'--preview', $preview_spec,
	# No --preview-width: no pane shown, previewer output goes to terminal
	) ;

open my $pipe, '|-', @cmd or die "Cannot run fzfw: $!\n" ;

for my $item (@items)
	{
	print $pipe "$item\n" ;
	}

close $pipe ;
