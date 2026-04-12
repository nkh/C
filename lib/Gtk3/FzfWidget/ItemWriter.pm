package Gtk3::FzfWidget::ItemWriter ;

# Writes items to fzf's stdin pipe in a forked child process so that the
# GTK main loop is never blocked.
#
# Item source protocol
# --------------------
# Items can be:
#   - An arrayref:   written in one pass, then the pipe is closed.
#   - A coderef:     called repeatedly as an iterator.  Each call must return
#                    either an arrayref of one or more items (strings) to write,
#                    or undef to signal that there are no more items.
#
# The coderef form allows the caller to produce items lazily — e.g. reading
# from a database cursor or a slow generator — without loading everything into
# memory at once.
#
# Usage
# -----
#   my $writer = Gtk3::FzfWidget::ItemWriter->new(
#       items => \@array,   # or items => \&iterator_coderef
#       fh    => $pipe_fh,  # write end of the stdin pipe to fzf
#   ) ;
#   $writer->start() ;      # forks the writer child; returns immediately
#   # ... later, on shutdown:
#   $writer->stop() ;       # kills writer child if still running
#
# The caller must call stop() before the pipe filehandle goes out of scope.

use strict ;
use warnings ;
use POSIX qw(WNOHANG _exit) ;
use Encode qw(encode_utf8 is_utf8) ;

our $VERSION = '0.01' ;

# Batch size: number of items written per syswrite call in the child.
# Larger batches reduce syscall overhead; smaller batches reduce pipe stalls.
my $WRITE_BATCH = 512 ;

# ------------------------------------------------------------------------------

sub new
{
my ($class, %args) = @_ ;

my $self =
	{
	items => $args{items},   # arrayref or coderef
	fh    => $args{fh},      # write end of the fzf stdin pipe
	pid   => undef,          # writer child pid
	} ;

return bless $self, $class ;
}

# ------------------------------------------------------------------------------

sub start
{
my ($self) = @_ ;

my $fh    = $self->{fh} ;
my $items = $self->{items} ;

my $pid = fork() ;

unless (defined $pid)
	{
	warn "ItemWriter: fork failed: $!" ;
	close $fh ;
	return 0 ;
	}

if ($pid == 0)
	{
	# Child: write all items then exit.
	# Do not touch GTK, Glib, or any filehandle except $fh.
	_write_items($fh, $items) ;
	close $fh ;
	_exit(0) ;
	}

# Parent: close write end (child has it), record pid.
close $fh ;
$self->{pid} = $pid ;

return 1 ;
}

# ------------------------------------------------------------------------------
# Called from the GTK main loop (e.g. death_watch timer) to reap the child
# without blocking.  Returns 1 if the child is still running, 0 if it exited.

sub reap
{
my ($self) = @_ ;

return 0 unless defined $self->{pid} ;

my $result = waitpid($self->{pid}, WNOHANG) ;

if ($result == $self->{pid} || $result == -1)
	{
	$self->{pid} = undef ;
	return 0 ;
	}

return 1 ;
}

# ------------------------------------------------------------------------------

sub stop
{
my ($self) = @_ ;

return unless defined $self->{pid} ;

kill 'TERM', $self->{pid} ;
waitpid($self->{pid}, 0) ;
$self->{pid} = undef ;
}

# ------------------------------------------------------------------------------
# Internal: runs in the forked child.  Never returns normally — calls _exit.

sub _write_items
{
my ($fh, $items) = @_ ;

binmode($fh, ':raw') ;

if (ref $items eq 'CODE')
	{
	# Iterator protocol: call until undef is returned.
	my $buf = '' ;

	while (1)
		{
		my $batch = $items->() ;
		last unless defined $batch ;

		# Accept either a single string or an arrayref of strings.
		my @lines = ref $batch eq 'ARRAY' ? @$batch : ($batch) ;

		for my $item (@lines)
			{
			next unless defined $item ;
			my $line = is_utf8($item) ? encode_utf8($item) : $item ;
			$buf .= $line . "\n" ;

			if (length($buf) >= $WRITE_BATCH * 80)
				{
				_flush($fh, \$buf) ;
				}
			}
		}

	_flush($fh, \$buf) if length $buf ;
	}
elsif (ref $items eq 'ARRAY')
	{
	my $buf  = '' ;
	my $n    = 0 ;

	for my $item (@$items)
		{
		next unless defined $item ;
		my $line = is_utf8($item) ? encode_utf8($item) : $item ;
		$buf .= $line . "\n" ;
		$n++ ;

		if ($n >= $WRITE_BATCH)
			{
			_flush($fh, \$buf) ;
			$n = 0 ;
			}
		}

	_flush($fh, \$buf) if length $buf ;
	}
}

# ------------------------------------------------------------------------------

sub _flush
{
my ($fh, $buf_ref) = @_ ;

return unless length $$buf_ref ;

my $total   = length $$buf_ref ;
my $written = 0 ;

while ($written < $total)
	{
	my $n = syswrite($fh, $$buf_ref, $total - $written, $written) ;
	last unless defined $n ;
	$written += $n ;
	}

$$buf_ref = '' ;
}

1 ;
