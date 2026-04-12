package Gtk3::FzfWidget::Previewer ;

# Manages the --preview subprocess for fzfw.
#
# Each cursor change spawns a new subprocess from the user-supplied preview
# command.  If a previous subprocess is still running when a new one is
# requested, the old one is killed first.
#
# Placeholder expansion in the command string:
#   {}               item text (shell-quoted)
#   {index}          original item index
#   {selected}       1 if the item is currently selected, 0 otherwise
#   {query}          current query string (shell-quoted)
#   {selected_list}  path to $tmpdir/selected_list (written only when used)
#   {port}           fzf HTTP listen port
#   {tmpdir}         per-session temp directory
#   {width}          preview pane pixel width
#   {height}         preview pane pixel height
#   {bg}             preview background CSS color
#   {fg}             preview foreground CSS color
#
# Output protocol — the previewer writes control line(s) before content:
#   TEXT:            remaining stdout is plain text
#   IMAGE:/path      display the image at /path
#   FILE:/path       load /path, auto-detect text vs image by extension
#   CACHE:           cache this call's output (overrides missing global flag)
#   NOCACHE:         do not cache this call (overrides global --preview-cache)
#
# CACHE: / NOCACHE: may appear before or after the content-type line.
# Remaining stdout after all control lines is the content (TEXT: only).
#
# Cache is stored in $tmpdir/{index} and deleted on object destruction.

use strict ;
use warnings ;
use POSIX qw(WNOHANG) ;
use Encode qw(decode_utf8 is_utf8) ;
use File::Basename qw(basename) ;
use Scalar::Util qw(weaken) ;

our $VERSION = '0.01' ;

my %IMAGE_EXTS = map { $_ => 1 } qw(
	png jpg jpeg gif bmp webp tiff tif svg ico
	) ;

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;

my $self =
	{
	spec          => $args{spec},          # raw command string with placeholders
	preview_pane  => $args{preview_pane},  # Gtk3::PreviewPane instance or undef
	cache         => $args{cache} // 0,    # global --preview-cache flag
	tmpdir        => $args{tmpdir},        # per-session temp directory
	port          => $args{port},          # fzf HTTP port
	colors        => $args{colors} // {},  # widget color hashref
	pid           => undef,                # current subprocess pid
	stdout_fh     => undef,                # read end of stdout pipe
	stderr_fh     => undef,                # read end of stderr pipe
	io_source     => undef,                # Glib IO watch id
	} ;

return bless $self, $class ;
}

# ------------------------------------------------------------------------------

sub invoke
{
my ($self, %args) = @_ ;

# args: text, index, selected, query, local_selected, preview_w, preview_h

$self->_kill_current() ;

my $pane = $self->{preview_pane} ;

my $cmd = $self->_expand
	(
	$self->{spec},
	%args,
	) ;

# Create pipes for stdout and stderr
pipe(my $out_r, my $out_w) or do { warn "pipe: $!" ; return } ;
pipe(my $err_r, my $err_w) or do { warn "pipe: $!" ; return } ;

my $pid = fork() ;

unless (defined $pid)
	{
	warn "fork: $!" ;
	return ;
	}

if ($pid == 0)
	{
	close $out_r ;
	close $err_r ;

	open(STDOUT, '>&', $out_w) or POSIX::_exit(1) ;
	open(STDERR, '>&', $err_w) or POSIX::_exit(1) ;

	close $out_w ;
	close $err_w ;

	{ no warnings 'exec' ; exec('/bin/sh', '-c', $cmd) }
	POSIX::_exit(127) ;
	}

close $out_w ;
close $err_w ;

$self->{pid}       = $pid ;
$self->{stdout_fh} = $out_r ;
$self->{stderr_fh} = $err_r ;
$self->{_args}     = \%args ;

# Watch stdout for output using Glib IO watch (non-blocking)
$out_r->blocking(0) ;
$err_r->blocking(0) ;

# Use a Glib timer to poll for process completion — same approach as the
# FzfWidget death watch, for the same reason (SIGCHLD unreliable in GTK).
my $self_ref = $self ;
weaken($self_ref) ;

$self->{io_source} = Glib::Timeout->add(
	50,
	sub
		{
		return 0 unless $self_ref ;
		return $self_ref->_poll_subprocess() ;
		},
	) ;
}

# ------------------------------------------------------------------------------

sub _poll_subprocess
{
my ($self) = @_ ;

return 0 unless defined $self->{pid} ;

my $result = waitpid($self->{pid}, WNOHANG) ;

return 1 if $result == 0 ;   # still running

my $exit_code = $? >> 8 ;
$self->{pid} = undef ;

my $stdout = _slurp_fh($self->{stdout_fh}) ;
my $stderr = _slurp_fh($self->{stderr_fh}) ;

close $self->{stdout_fh} if $self->{stdout_fh} ;
close $self->{stderr_fh} if $self->{stderr_fh} ;
$self->{stdout_fh} = undef ;
$self->{stderr_fh} = undef ;
$self->{io_source}  = undef ;

# Decode byte output to Perl Unicode strings for correct display in GTK
$stdout = decode_utf8($stdout) if defined $stdout && !is_utf8($stdout) ;
$stderr = decode_utf8($stderr) if defined $stderr && !is_utf8($stderr) ;

if ($exit_code != 0)
	{
	$self->_show_error($stderr || "previewer exited with code $exit_code") ;
	return 0 ;
	}

$self->_handle_output($stdout, $self->{_args}) ;

return 0 ;
}

# ------------------------------------------------------------------------------

sub _handle_output
{
my ($self, $output, $args) = @_ ;

return unless defined $output && length $output ;

my @lines   = split /\n/, $output, -1 ;
my $content_type = undef ;
my $cache_control = undef ;   # 'cache', 'nocache', or undef (use global)
my @content_lines ;
my $parsing_control = 1 ;

for my $line (@lines)
	{
	if ($parsing_control)
		{
		if ($line eq 'CACHE:')       { $cache_control = 'cache'   ; next }
		if ($line eq 'NOCACHE:')     { $cache_control = 'nocache' ; next }
		if ($line =~ /^TEXT:/)       { $content_type = 'text'  ; push @content_lines, substr($line, 5) ; $parsing_control = 0 ; next }
		if ($line =~ /^IMAGE:(.+)/)  { $content_type = 'image' ; push @content_lines, $1 ; $parsing_control = 0 ; next }
		if ($line =~ /^FILE:(.+)/)   { $content_type = 'file'  ; push @content_lines, $1 ; $parsing_control = 0 ; next }

		# No recognised control line — treat entire output as plain text
		$content_type = 'text' ;
		push @content_lines, $line ;
		$parsing_control = 0 ;
		}
	else
		{
		push @content_lines, $line ;
		}
	}

$content_type //= 'text' ;

# Determine whether to cache
my $do_cache = $cache_control
	? ($cache_control eq 'cache' ? 1 : 0)
	: $self->{cache} ;

my $pane = $self->{preview_pane} ;

if ($content_type eq 'text')
	{
	my $text = join("\n", @content_lines) ;

	if ($do_cache && defined $args->{index})
		{
		_write_cache($self->{tmpdir}, $args->{index}, $output) ;
		}

	$pane->load_text_string($text) if $pane ;
	}
elsif ($content_type eq 'image')
	{
	my $path = $content_lines[0] // '' ;
	$pane->load($path) if $pane && -f $path ;
	}
elsif ($content_type eq 'file')
	{
	my $path = $content_lines[0] // '' ;

	if ($do_cache && defined $args->{index})
		{
		_write_cache($self->{tmpdir}, $args->{index}, $output) ;
		}

	$pane->load($path) if $pane && -f $path ;
	}
}

# ------------------------------------------------------------------------------

sub _show_error
{
my ($self, $msg) = @_ ;

my $pane = $self->{preview_pane} ;
return unless $pane ;

$pane->load_text_string("Preview error:\n\n$msg") ;
}

# ------------------------------------------------------------------------------

sub _expand
{
my ($self, $spec, %args) = @_ ;

my $text          = $args{text}           // '' ;
my $index         = $args{index}          // 0 ;
my $selected      = $args{selected}       // 0 ;
my $query         = $args{query}          // '' ;
my $local_selected = $args{local_selected} // {} ;
my $width         = $args{preview_w}      // 0 ;
my $height        = $args{preview_h}      // 0 ;
my $port          = $self->{port}         // '' ;
my $tmpdir        = $self->{tmpdir}       // '' ;
my $bg            = $self->{colors}{widget_bg} // '' ;
my $fg            = $self->{colors}{widget_fg} // '' ;

# Write selected_list file only when the placeholder is present
if ($spec =~ /\{selected_list\}/)
	{
	my $path = "$tmpdir/selected_list" ;
	open my $fh, '>', $path or warn "cannot write selected_list: $!" ;

	if ($fh)
		{
		for my $idx (sort { $a <=> $b } keys %$local_selected)
			{
			print $fh "$idx\t$local_selected->{$idx}\n" ;
			}

		close $fh ;
		}

	$spec =~ s/\{selected_list\}/_shell_quote($path)/ge ;
	}

$spec =~ s/\{\}/_shell_quote($text)/ge ;
$spec =~ s/\{index\}/$index/g ;
$spec =~ s/\{selected\}/$selected/g ;
$spec =~ s/\{query\}/_shell_quote($query)/ge ;
$spec =~ s/\{port\}/$port/g ;
$spec =~ s/\{tmpdir\}/_shell_quote($tmpdir)/ge ;
$spec =~ s/\{width\}/$width/g ;
$spec =~ s/\{height\}/$height/g ;
$spec =~ s/\{bg\}/_shell_quote($bg)/ge ;
$spec =~ s/\{fg\}/_shell_quote($fg)/ge ;

return $spec ;
}

# ------------------------------------------------------------------------------

sub _kill_current
{
my ($self) = @_ ;

if ($self->{io_source})
	{
	Glib::Source->remove($self->{io_source}) ;
	$self->{io_source} = undef ;
	}

if (defined $self->{pid})
	{
	kill 'TERM', $self->{pid} ;
	waitpid($self->{pid}, 0) ;
	$self->{pid} = undef ;
	}

for my $fh (qw(stdout_fh stderr_fh))
	{
	close $self->{$fh} if $self->{$fh} ;
	$self->{$fh} = undef ;
	}
}

# ------------------------------------------------------------------------------

sub cleanup
{
my ($self) = @_ ;

$self->_kill_current() ;

if ($self->{tmpdir} && -d $self->{tmpdir})
	{
	# Remove cache files and the temp directory
	opendir my $dh, $self->{tmpdir} or return ;
	my @files = readdir $dh ;
	closedir $dh ;

	for my $f (@files)
		{
		next if $f eq '.' || $f eq '..' ;
		unlink "$self->{tmpdir}/$f" ;
		}

	rmdir $self->{tmpdir} ;
	}
}

# ------------------------------------------------------------------------------

sub _slurp_fh
{
my ($fh) = @_ ;

return '' unless $fh ;

my $buf = '' ;
my $chunk ;

while (defined($chunk = <$fh>))
	{
	$buf .= $chunk ;
	}

return $buf ;
}

# ------------------------------------------------------------------------------

sub _write_cache
{
my ($tmpdir, $index, $content) = @_ ;

return unless defined $tmpdir && defined $index ;

open my $fh, '>', "$tmpdir/$index" or return ;
print $fh $content ;
close $fh ;
}

# ------------------------------------------------------------------------------

sub _shell_quote
{
my ($s) = @_ ;

$s =~ s/'/'\\''/g ;

return "'$s'" ;
}

1 ;
