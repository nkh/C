use strict ;
use warnings ;
use Module::Build ;

my $build = Module::Build->new
	(
	module_name        => 'Gtk3::FzfWidget',
	license            => 'artistic_2',
	dist_author        => 'nkh',
	dist_version_from  => 'lib/Gtk3/FzfWidget.pm',
	dist_abstract      => 'GTK3 fuzzy-search widget powered by fzf',

	requires =>
		{
		'perl'             => '5.020',
		'Gtk3'             => '0',
		'Glib'             => '0',
		'IO::Pty'          => '0',
		'IO::Socket::INET' => '0',
		'JSON::PP'         => '0',
		'POSIX'            => '0',
		'Fcntl'            => '0',
		'File::Basename'   => '0',
		'List::Util'       => '0',
		'Encode'           => '0',
		},

	build_requires =>
		{
		'Test::More'      => '0',
		'Test::Exception' => '0',
		},

	recommends =>
		{
		'Getopt::Long' => '0',
		},

	script_files => ['script/fzfw'],

	meta_merge =>
		{
		resources =>
			{
			repository => 'https://github.com/nkh/P5-Fzf-Preview-Gtk3',
			bugtracker => 'https://github.com/nkh/P5-Fzf-Preview-Gtk3/issues',
			},
		},
	) ;

$build->create_build_script() ;
