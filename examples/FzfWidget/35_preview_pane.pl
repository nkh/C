#!/usr/bin/perl

# Example 35 — --preview with a pane in the window.
#
# Demonstrates:
#   - --preview: external script called on each cursor change
#   - TEXT: and IMAGE: output protocols
#   - --preview-cache: output cached by item index
#   - --preview-width: fraction of window width for the preview pane
#   - Placeholders: {} {index} {selected} {query} {width} {height}
#
# The previewer (35_preview_pane.sh) inspects the file under the cursor:
#   - Image files  -> IMAGE:/path  (displayed in the preview pane)
#   - Text files   -> TEXT: + file content (displayed in the preview pane)
#   - PDF files    -> TEXT: + pdftotext output (if installed)
#
# Run: perl 35_preview_pane.pl [directory]
#      perl 35_preview_pane.pl /usr/share/doc

use strict ;
use warnings ;
use lib '../lib' ;
use FindBin ;
use File::Basename qw(dirname) ;
use Cwd qw(abs_path) ;

my $dir    = $ARGV[0] // '.' ;
my $script = abs_path(dirname(__FILE__)) . '/35_preview_pane.sh' ;

die "previewer not found: $script\n"      unless -f $script ;
die "previewer not executable: $script\n" unless -x $script ;

opendir my $dh, $dir or die "Cannot open $dir: $!\n" ;
my @files = sort
	map  { "$dir/$_" }
	grep { !/^\.\.?$/ }
	readdir $dh ;
closedir $dh ;

die "No files found in $dir\n" unless @files ;

# Placeholders:
#   {}         item text (the file path, shell-quoted by fzfw)
#   {index}    original item index
#   {selected} 1 if item is selected, 0 otherwise
#   {query}    current query string (shell-quoted by fzfw)
#   {width}    preview pane pixel width
#   {height}   preview pane pixel height

my $preview_spec = "$script {} {index} {selected} {query} {width} {height}" ;

my @cmd =
	(
	'perl', "$FindBin::Bin/../script/fzfw",
	'--theme',         'dark',
	'--preview',       $preview_spec,
	'--preview-cache',
	'--preview-width', '0.55',
	'--no-buttons',
	'--header',        'File browser — cursor moves update preview',
	) ;

open my $pipe, '|-', @cmd or die "Cannot run fzfw: $!\n" ;

for my $f (@files)
	{
	print $pipe "$f\n" ;
	}

close $pipe ;
