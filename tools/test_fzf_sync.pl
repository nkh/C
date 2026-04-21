#!/usr/bin/perl

# test_fzf_sync.pl — tests fzf query synchronisation at scale, no GTK needed.
#
# Usage:
#   perl test_fzf_sync.pl [--items N] [--query STR] [--timeout MS] [--port P]
#
# Examples:
#   perl test_fzf_sync.pl --items 1000
#   perl test_fzf_sync.pl --items 100000 --query xyz --timeout 10000
#   perl test_fzf_sync.pl --items 500000 --query ent --timeout 30000

use strict ;
use warnings ;
use Getopt::Long ;
use IO::Socket::INET ;
use POSIX qw(WNOHANG _exit) ;
use Time::HiRes qw(gettimeofday sleep) ;

my $opt_items   = 10_000 ;
my $opt_query   = 'abc' ;
my $opt_timeout = 8_000 ;
my $opt_port    = 0 ;
my $opt_limit   = 200 ;

GetOptions(
	'items=i'   => \$opt_items,
	'query=s'   => \$opt_query,
	'timeout=i' => \$opt_timeout,
	'port=i'    => \$opt_port,
	'limit=i'   => \$opt_limit,
	) or die "Usage: $0 [--items N] [--query STR] [--timeout MS]\n" ;

sub ts { sprintf "[%.3f]", (gettimeofday())[0] + (gettimeofday())[1]/1e6 }

# ── Find a free port ──────────────────────────────────────────────────────────

if ($opt_port == 0)
	{
	my $sock = IO::Socket::INET->new(
		Listen    => 1,
		LocalAddr => '127.0.0.1',
		LocalPort => 0,
		Proto     => 'tcp',
		) ;
	$opt_port = $sock->sockport() ;
	$sock->close() ;
	}

printf "%s Config: items=%d query='%s' timeout=%dms port=%d limit=%d\n",
	ts(), $opt_items, $opt_query, $opt_timeout, $opt_port, $opt_limit ;

# ── Start fzf with piped stdin ────────────────────────────────────────────────

pipe(my $stdin_r, my $stdin_w) or die "pipe: $!" ;

my $fzf_pid = fork() ;
die "fork: $!" unless defined $fzf_pid ;

if ($fzf_pid == 0)
	{
	close $stdin_w ;
	open(STDIN, '<&', $stdin_r) or die "dup stdin: $!" ;
	close $stdin_r ;
	open(STDOUT, '>', '/dev/null') ;
	open(STDERR, '>', '/dev/null') ;
	exec('fzf', "--listen=$opt_port", '--no-sort') ;
	die "exec fzf: $!" ;
	}

close $stdin_r ;

# Wait for fzf HTTP server
{
my $t0 = gettimeofday() ;
my $up = 0 ;
while (gettimeofday() - $t0 < 10)
	{
	my $s = IO::Socket::INET->new(PeerHost=>'127.0.0.1', PeerPort=>$opt_port,
	                               Proto=>'tcp', Timeout=>0.1) ;
	if ($s) { $s->close() ; $up = 1 ; last }
	Time::HiRes::sleep(0.05) ;
	}
die "fzf did not start\n" unless $up ;
printf "%s fzf ready (port %d)\n", ts(), $opt_port ;
}

# ── Write items to fzf stdin in a child ───────────────────────────────────────

my $writer_pid = fork() ;
die "fork writer: $!" unless defined $writer_pid ;

if ($writer_pid == 0)
	{
	my $t = gettimeofday() ;
	for my $i (1 .. $opt_items)
		{
		printf $stdin_w "entry_%06d_abcdefgh_%s\n", $i,
			join('', map { ('a'..'z')[int(rand(26))] } 1..8) ;
		}
	close $stdin_w ;
	printf STDERR "%s writer: wrote %d items in %.3fs\n", ts(), $opt_items, gettimeofday()-$t ;
	_exit(0) ;
	}

close $stdin_w ;

# ── HTTP helpers ──────────────────────────────────────────────────────────────

sub http_get
{
my ($path, $timeout_ms) = @_ ;
my $deadline = gettimeofday() + $timeout_ms/1000 ;
my $sock = IO::Socket::INET->new(PeerHost=>'127.0.0.1', PeerPort=>$opt_port,
                                  Proto=>'tcp', Timeout=>$timeout_ms/1000) ;
return (undef, $timeout_ms/1000) unless $sock ;
$sock->autoflush(1) ;
my $t0 = gettimeofday() ;
print $sock "GET $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" ;
my ($body, $in_body) = ('', 0) ;
while (defined(my $line = $sock->getline()))
	{
	if (!$in_body) { $in_body = 1 if $line eq "\r\n" ; next }
	$body .= $line ;
	}
$sock->close() ;
return ($body, gettimeofday() - $t0) ;
}

sub http_post
{
my ($body) = @_ ;
my $sock = IO::Socket::INET->new(PeerHost=>'127.0.0.1', PeerPort=>$opt_port,
                                  Proto=>'tcp', Timeout=>2) ;
return 0 unless $sock ;
$sock->autoflush(1) ;
my $len = length($body) ;
print $sock "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: $len\r\nConnection: close\r\n\r\n$body" ;
eval { local $/ ; <$sock> } ;
$sock->close() ;
return 1 ;
}

sub parse_mc_tc
{
my ($json) = @_ ;
return (0, 0) unless $json ;
my $mc = ($json =~ /"matchCount"\s*:\s*(\d+)/) ? $1 : 0 ;
my $tc = ($json =~ /"totalCount"\s*:\s*(\d+)/) ? $1 : 0 ;
my @idx = ($json =~ /"index"\s*:\s*(\d+)/g) ;
return ($mc, $tc, \@idx) ;
}

# ── Test 1: wait for all items to be indexed ──────────────────────────────────

print "\n── Test 1: indexing progress ──\n" ;
my $t_start = gettimeofday() ;
my $indexed = 0 ;

for my $i (1..300)
	{
	my ($resp, $elapsed) = http_get('/?limit=1', $opt_timeout) ;
	my ($mc, $tc) = parse_mc_tc($resp) ;
	printf "%s  poll %3d: mc=%-8d tc=%-8d get=%.3fs\n", ts(), $i, $mc, $tc, $elapsed ;
	if ($tc >= $opt_items) { $indexed = 1 ; last }
	Time::HiRes::sleep(0.2) ;
	}

printf "%s Indexing: %.3fs indexed=%d\n\n", ts(), gettimeofday()-$t_start, $indexed ;

# ── Test 2: query timing at varying delays after POST ─────────────────────────

print "── Test 2: delay between POST change-query and GET ──\n" ;
printf "%-10s %-8s %-8s %-8s %-10s %s\n",
	'delay_ms', 'mc', 'tc', 'indices', 'total_ms', 'note' ;

for my $delay_ms (0, 5, 10, 20, 50, 100, 200, 500, 1000)
	{
	# Reset query
	http_post("change-query()") ;
	Time::HiRes::sleep(0.3) ;

	my $t0 = gettimeofday() ;
	http_post("change-query($opt_query)") ;
	Time::HiRes::sleep($delay_ms / 1000) if $delay_ms ;
	my ($resp, $get_ms) = http_get("/?limit=$opt_limit", $opt_timeout) ;
	my $total_ms = int((gettimeofday() - $t0) * 1000) ;
	my ($mc, $tc, $idx) = parse_mc_tc($resp) ;

	my $note = $mc == 0         ? 'EMPTY - fzf not done'
	         : $mc == $opt_items ? 'unfiltered - same as empty query'
	         : 'filtered OK' ;

	printf "%-10d %-8d %-8d %-8d %-10d %s\n",
		$delay_ms, $mc, $tc, scalar @$idx, $total_ms, $note ;
	}

# ── Test 3: poll until results stabilise after query ─────────────────────────

print "\n── Test 3: poll until mc stabilises after change-query ──\n" ;
http_post("change-query()") ;
Time::HiRes::sleep(0.5) ;
my ($r0) = http_get('/?limit=1', 2000) ;
my ($baseline) = parse_mc_tc($r0) ;
printf "Baseline mc (empty query): %d\n", $baseline ;

http_post("change-query($opt_query)") ;
my $t_post = gettimeofday() ;
my ($prev, $stable_count, $stable_mc) = ($baseline, 0, undef) ;

for my $p (1..200)
	{
	Time::HiRes::sleep(0.025) ;
	my ($resp) = http_get('/?limit=1', $opt_timeout) ;
	my ($mc) = parse_mc_tc($resp) ;
	my $ms = int((gettimeofday() - $t_post) * 1000) ;
	my $flag = '' ;

	if ($mc != $prev)
		{
		$flag = " ← mc changed ($prev → $mc)" ;
		$stable_count = 0 ;
		$stable_mc = $mc ;
		}
	elsif (defined $stable_mc && $mc == $stable_mc && $mc != $baseline)
		{
		$stable_count++ ;
		$flag = " [stable $stable_count]" ;
		}

	printf "  poll %3d  %5dms  mc=%-8d%s\n", $p, $ms, $mc, $flag ;
	$prev = $mc ;

	last if $stable_count >= 3 ;
	last if $ms > $opt_timeout ;
	}

printf "\n%s Minimum delay needed: %dms for '%s' with %d items\n",
	ts(), int((gettimeofday()-$t_post)*1000), $opt_query, $opt_items ;

# ── Cleanup ───────────────────────────────────────────────────────────────────

waitpid($writer_pid, 0) ;
kill 'TERM', $fzf_pid ;
waitpid($fzf_pid, 0) ;
print ts() . " Done.\n" ;
