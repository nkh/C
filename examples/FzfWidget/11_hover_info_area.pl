#!/usr/bin/perl

use strict ;
use warnings ;
use lib '../lib' ;
use Gtk3 -init ;
use Gtk3::FzfWidget ;
use POSIX qw(strftime) ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->set_title('11 - hover info area') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

# List files in current directory
opendir(my $dh, '.') or die $! ;
my @files = sort grep { !/^\.\.?$/ } readdir($dh) ;
closedir($dh) ;

my $widget = Gtk3::FzfWidget->new(
	items  => \@files,
	config =>
		{
		theme       => 'dark',
		info_height => 72,
		on_hover    => sub
			{
			my ($w, $text, $idx) = @_ ;
			my @st = stat($text) ;
			return '' unless @st ;
			my $size  = $st[7] ;
			my $mtime = strftime('%Y-%m-%d %H:%M', localtime($st[9])) ;
			my $type  = -d $text ? 'directory'
			          : -x $text ? 'executable'
			          : -l $text ? 'symlink'
			          :             'file' ;
			return sprintf "%s\ntype: %s\nsize: %s\nmodified: %s",
				$text, $type,
				$size >= 1_048_576 ? sprintf('%.1f MB', $size / 1_048_576)
				: $size >= 1024    ? sprintf('%.1f KB', $size / 1024)
				: "$size bytes",
				$mtime ;
			},
		on_confirm => sub
			{
			my ($w, $sel, $query) = @_ ;
			print "$_->[0]\n" for @$sel ;
			Gtk3->main_quit() ;
			},
		on_cancel => sub { Gtk3->main_quit() },
		},
	) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
