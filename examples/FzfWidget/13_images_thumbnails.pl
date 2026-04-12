#!/usr/bin/perl

# Comprehensive example: file browser with thumbnails, colored type indicators,
# hover info, and transform_fn. Demonstrates image_fn, on_hover, row_striping.
#
# Usage: perl text_and_images.pl [directory]

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;
use POSIX qw(strftime) ;

Gtk3->init() ;

my $dir = $ARGV[0] // '.' ;

opendir(my $dh, $dir) or die "Cannot open $dir: $!" ;
my @files = map  { "$dir/$_" }
            sort
            grep { !/^\.\.\?$/ }
            readdir($dh) ;
closedir($dh) ;

die "No files in $dir\n" unless @files ;

my %IMAGE_EXTS = map { $_ => 1 } qw(png jpg jpeg gif bmp webp tiff svg) ;

# Type-to-color mapping for square indicators
my %TYPE_RGB =
	(
	pl  => [100, 149, 237],
	pm  => [100, 149, 237],
	py  => [255, 215,   0],
	sh  => [144, 238, 144],
	rb  => [220,  20,  60],
	c   => [ 70, 130, 180],
	h   => [ 70, 130, 180],
	md  => [255, 165,   0],
	txt => [200, 200, 200],
	pdf => [220,  20,  60],
	) ;

# Build a solid-color pixbuf using raw packed bytes — works on all GTK3 versions
sub colored_square
{
my ($r, $g, $b, $size) = @_ ;
$size //= 32 ;
my $row  = pack('C*', ($r, $g, $b) x $size) ;
my $data = $row x $size ;
return Gtk3::Gdk::Pixbuf->new_from_data($data, 'rgb', 0, 8, $size, $size, $size * 3) ;
}

my $image_fn = sub
	{
	my ($path, $idx) = @_ ;

	my ($ext) = lc($path) =~ /\.([^.\/]+)$/ ;
	$ext //= '' ;

	# Real image file — load as thumbnail
	if ($IMAGE_EXTS{$ext} && -r $path)
		{
		my $pb = eval
			{
			Gtk3::Gdk::Pixbuf->new_from_file_at_scale($path, 48, 48, 1) ;
			} ;
		return $pb if defined $pb ;
		}

	# Non-image file — return a colored type indicator square
	my $rgb = $TYPE_RGB{$ext} // [128, 128, 128] ;
	return colored_square(@$rgb, 32) ;
	} ;

my $transform_fn = sub
	{
	my ($path) = @_ ;
	$path =~ s|.*/|| ;
	return $path ;
	} ;

my $on_hover = sub
	{
	my ($w, $path, $idx) = @_ ;

	my @st = stat($path) ;
	return '' unless @st ;

	my $size = $st[7] ;
	my $size_str =
		  $size >= 1_048_576 ? sprintf('%.1f MB', $size / 1_048_576)
		: $size >= 1024      ? sprintf('%.1f KB', $size / 1024)
		:                      "$size bytes" ;

	my $mtime = strftime('%Y-%m-%d %H:%M', localtime($st[9])) ;
	my $type  = -d $path ? 'directory'
	          : -l $path ? 'symlink'
	          : -x $path ? 'executable'
	          :             'file' ;

	return sprintf "%s\ntype: %s  size: %s  modified: %s",
		$path, $type, $size_str, $mtime ;
	} ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title("fzfw — $dir") ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@files,
	config =>
		{
		theme            => 'dark',
		font_family      => 'Monospace',
		font_size        => 13,
		image_max_width  => 48,
		image_max_height => 48,
		image_fn         => $image_fn,
		transform_fn     => $transform_fn,
		info_height      => 72,
		on_hover         => $on_hover,
		header           => sprintf("%s  (%d entries)", $dir, scalar @files),
		on_confirm       => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel        => sub { Gtk3->main_quit() },
		on_ready         => sub
			{
			my ($w) = @_ ;
			printf STDERR "loaded %d items\n", $w->get_total_count() ;
			},
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
