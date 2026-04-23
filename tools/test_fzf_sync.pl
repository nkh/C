#!/usr/bin/perl

# test_fzf_sync.pl — measures fzf query latency at scale. No GTK needed.
#
# PURPOSE
# -------
# The widget sends change-query to fzf via HTTP POST, then immediately
# does a GET to fetch filtered results. If fzf hasn't finished computing
# the new match list yet, the GET returns stale results and the display
# does not update.
#
# This script measures:
#   Test 1 — how long fzf takes to index N items
#   Test 2 — minimum delay between POST change-query and GET for correct results
#   Test 3 — exact latency until fzf's match count stabilises
#
# HOW TO RUN
# ----------
#   perl test_fzf_sync.pl                              # 10k items, query 'abc'
#   perl test_fzf_sync.pl --items 100000 --query xyz
#   perl test_fzf_sync.pl --items 500000 --query ent --timeout 30000
#
# Output goes ONLY to log file (default /tmp/fzf_sync_test.log).
# Watch it live:  tail -f /tmp/fzf_sync_test.log
#
# READING THE OUTPUT
# ------------------
# Test 1: "Indexing complete Ns" — time for fzf to see all items.
#
# Test 2: for each delay (0ms, 10ms, 50ms...) reports:
#   "filtered OK"   — GET returned correct filtered results
#   "SAME AS EMPTY" — fzf hadn't processed the query yet (stale)
#   "TIMEOUT"       — no response within --timeout ms
#
#   The SMALLEST delay showing "filtered OK" is the minimum the widget
#   must wait between POST and GET.  If 2000ms still shows "SAME AS EMPTY",
#   the StatePoller timeout (2000ms) will always fail for this dataset size.
#
# Test 3: polls every 25ms, shows when matchCount first changes.
#   "fzf search latency = Nms" is the key number.
#   If this exceeds StatePoller timeout_ms (2000ms), increase it.

use strict ;
use warnings ;
use Getopt::Long ;
use IO::Socket::INET ;
use IO::Pty ;
use POSIX qw(WNOHANG _exit) ;
use Time::HiRes qw(gettimeofday sleep) ;

my $opt_items   = 10_000 ;
my $opt_query   = 'abc' ;
my $opt_timeout = 8_000 ;
my $opt_port    = 0 ;
my $opt_limit   = 200 ;
my $opt_log     = '/tmp/fzf_sync_test.log' ;

GetOptions(
	'items=i'   => \$opt_items,
	'query=s'   => \$opt_query,
	'timeout=i' => \$opt_timeout,
	'port=i'    => \$opt_port,
	'limit=i'   => \$opt_limit,
	'log=s'     => \$opt_log,
	) or die "Usage: $0 [--items N] [--query STR] [--timeout MS] [--log FILE]\n" ;

open(my $LOG, '>', $opt_log) or die "Cannot open $opt_log: $!" ;
$LOG->autoflush(1) ;

sub log_line
{
my ($msg) = @_ ;
my ($sec, $usec) = gettimeofday() ;
printf $LOG "[%.3f] %s\n", $sec + $usec / 1e6, $msg ;
}

# ── Pick a free port ──────────────────────────────────────────────────────────

if ($opt_port == 0)
	{
	my $sock = IO::Socket::INET->new(
		Listen    => 1,
		LocalAddr => '127.0.0.1',
		LocalPort => 0,
		Proto     => 'tcp',
		ReuseAddr => 1,
		) ;
	$opt_port = $sock->sockport() ;
	$sock->close() ;
	}

log_line("START items=$opt_items query='$opt_query' timeout=${opt_timeout}ms port=$opt_port") ;
print "Running. Output -> $opt_log\n" ;
print "Watch with: tail -f $opt_log\n" ;

# ── Launch fzf using a PTY (fzf requires a terminal for output) ───────────────

pipe(my $stdin_r, my $stdin_w) or die "pipe: $!" ;
my $pty = IO::Pty->new() ;

my $fzf_pid = fork() ;
die "fork: $!" unless defined $fzf_pid ;

if ($fzf_pid == 0)
	{
	$pty->make_slave_controlling_terminal() ;
	my $slave = $pty->slave() ;

	close $stdin_w ;
	POSIX::dup2(fileno($stdin_r), 0) ;
	close $stdin_r ;

	open(my $null, '>', '/dev/null') or _exit(1) ;
	POSIX::dup2(fileno($null), 1) ;
	POSIX::dup2(fileno($null), 2) ;
	close $null ;
	close $slave ;

	{ no warnings 'exec' ; exec('fzf', "--listen=$opt_port", '--no-sort') }
	die "exec fzf failed: $!" ;
	}

close $stdin_r ;

# ── Wait for fzf HTTP server ──────────────────────────────────────────────────

{
my $t0   = gettimeofday() ;
my $up   = 0 ;

while (gettimeofday() - $t0 < 15)
	{
	my $sock = IO::Socket::INET->new(
		PeerHost => '127.0.0.1',
		PeerPort => $opt_port,
		Proto    => 'tcp',
		Timeout  => 0.1,
		) ;
	if ($sock) { $sock->close() ; $up = 1 ; last }
	Time::HiRes::sleep(0.05) ;
	}

unless ($up)
	{
	log_line("FAIL: fzf HTTP server did not start within 15s") ;
	print "FAIL — see $opt_log\n" ;
	exit 1 ;
	}

log_line(sprintf "fzf ready (%.3fs)", gettimeofday() - $t0) ;
}

# ── Write items in a forked child ─────────────────────────────────────────────

my $writer_pid = fork() ;
die "fork writer: $!" unless defined $writer_pid ;

if ($writer_pid == 0)
	{
	for my $i (1 .. $opt_items)
		{
		printf $stdin_w "entry_%06d_%s\n", $i,
			join('', map { ('a'..'z')[int(rand(26))] } 1..8) ;
		}
	close $stdin_w ;
	_exit(0) ;
	}

close $stdin_w ;

# ── HTTP helpers ──────────────────────────────────────────────────────────────

sub get_state
{
my ($limit, $timeout_ms) = @_ ;

my $sock = IO::Socket::INET->new(
	PeerHost => '127.0.0.1',
	PeerPort => $opt_port,
	Proto    => 'tcp',
	Timeout  => $timeout_ms / 1000,
	) ;
return undef unless $sock ;

$sock->autoflush(1) ;
printf $sock "GET /?limit=%d HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", $limit ;

my ($body, $in_body) = ('', 0) ;
while (defined(my $line = $sock->getline()))
	{
	if (!$in_body) { $in_body = 1 if $line eq "\r\n" ; next }
	$body .= $line ;
	}
$sock->close() ;

my $mc = ($body =~ /"matchCount"\s*:\s*(\d+)/) ? $1 : 0 ;
my $tc = ($body =~ /"totalCount"\s*:\s*(\d+)/) ? $1 : 0 ;
my @idx = ($body =~ /"index"\s*:\s*(\d+)/g) ;
my $raw = substr($body, 0, 120) ;
$raw =~ s/\n/ /g ;

return { mc => $mc, tc => $tc, n => scalar @idx, raw => $raw } ;
}

sub send_query
{
my ($q) = @_ ;

my $sock = IO::Socket::INET->new(
	PeerHost => '127.0.0.1',
	PeerPort => $opt_port,
	Proto    => 'tcp',
	Timeout  => 5,
	) ;
return "CONNECT_FAIL" unless $sock ;

$sock->autoflush(1) ;
my $body = "change-query($q)" ;
my $len  = length($body) ;
printf $sock "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
	$len, $body ;

my $status = $sock->getline() // '' ;
chomp $status ;
eval { local $/ ; my $dummy = <$sock> } ;
$sock->close() ;

return $status ;
}

# ── Test 1: wait for indexing to complete ────────────────────────────────────

log_line("") ;
log_line("=== Test 1: indexing — wait for totalCount to reach $opt_items ===") ;

my $t_idx   = gettimeofday() ;
my $indexed = 0 ;

for my $i (1..600)
	{
	my $s = get_state(1, 5000) ;
	log_line(sprintf "  poll %3d: tc=%-8d mc=%-8d", $i, $s->{tc}, $s->{mc}) ;
	if ($s->{tc} >= $opt_items) { $indexed = 1 ; last }
	Time::HiRes::sleep(0.2) ;
	}

my $idx_time = gettimeofday() - $t_idx ;
log_line(sprintf "Indexing complete: %.3fs", $idx_time) ;

unless ($indexed)
	{
	log_line("ABORT: fzf did not index all items within timeout") ;
	kill 'TERM', $fzf_pid ;
	waitpid($fzf_pid, 0) ;
	print "ABORT — see $opt_log\n" ;
	exit 1 ;
	}

# ── Test 2: delay between POST and GET ───────────────────────────────────────

log_line("") ;
log_line("=== Test 2: minimum delay between POST change-query and GET ===") ;

send_query('') ;
Time::HiRes::sleep(0.3) ;
my $base_s = get_state(1, 5000) ;
my $base   = $base_s ? $base_s->{mc} : 0 ;
log_line("Baseline (empty query) mc = $base") ;
log_line(sprintf "%-8s %-8s %-8s %-12s %-12s %s", "delay_ms","mc","tc","total_ms","POST_status","result") ;

for my $delay (0, 5, 10, 20, 50, 100, 200, 500, 1000, 2000)
	{
	send_query('') ;
	Time::HiRes::sleep(0.3) ;

	my $t0          = gettimeofday() ;
	my $post_status = send_query($opt_query) ;
	Time::HiRes::sleep($delay / 1000) if $delay ;
	my $s           = get_state($opt_limit, $opt_timeout) ;
	my $total_ms    = int((gettimeofday() - $t0) * 1000) ;

	my ($mc, $tc, $raw) = $s ? ($s->{mc}, $s->{tc}, $s->{raw}) : (0, 0, '') ;

	my $result = !$s           ? "TIMEOUT"
	           : $mc == 0      ? "EMPTY — query not processed yet"
	           : $mc == $base  ? "SAME AS EMPTY — stale result"
	           :                 sprintf "filtered OK  mc=%d  (%.1f%% of %d)",
	                               $mc, 100 * $mc / $opt_items, $opt_items ;

	log_line(sprintf "  delay=%-5dms  mc=%-7d  tc=%-7d  total=%-6dms  POST=%-20s  %s",
		$delay, $mc, $tc, $total_ms, $post_status, $result) ;
	log_line("    raw=$raw") if $raw ;
	}

# ── Test 3: poll until mc stabilises ─────────────────────────────────────────

log_line("") ;
log_line("=== Test 3: fzf search latency (poll every 25ms after POST) ===") ;

send_query('') ;
Time::HiRes::sleep(0.5) ;
my $bmc_s = get_state(1, 5000) ;
my $bmc   = $bmc_s ? $bmc_s->{mc} : 0 ;
log_line("Baseline mc = $bmc  — sending change-query($opt_query)") ;

my $post3  = send_query($opt_query) ;
log_line("POST response: $post3") ;

my $t3           = gettimeofday() ;
my ($prev, $stable, $first_ms) = ($bmc, 0, undef) ;

for my $p (1..400)
	{
	Time::HiRes::sleep(0.025) ;
	my $s  = get_state(1, $opt_timeout) ;
	my $mc = $s ? $s->{mc} : 0 ;
	my $ms = int((gettimeofday() - $t3) * 1000) ;

	my $note = '' ;
	if ($mc != $prev)
		{
		$first_ms //= $ms ;
		$stable    = 0 ;
		$note      = "  <- CHANGED $prev -> $mc" ;
		}
	elsif (defined $first_ms)
		{
		$stable++ ;
		$note = "  [stable $stable/3]" ;
		}

	log_line(sprintf "  poll %3d  %5dms  mc=%-7d%s", $p, $ms, $mc, $note) ;
	$prev = $mc ;
	last if $stable >= 3 || $ms > $opt_timeout ;
	}

my $latency = defined $first_ms ? "${first_ms}ms" : ">${opt_timeout}ms (TIMEOUT)" ;
log_line("") ;
log_line("fzf search latency for '$opt_query' with $opt_items items: $latency") ;
if (defined $first_ms)
	{
	my $rec = $first_ms * 4 ;
	log_line("StatePoller timeout_ms should be >= $rec") ;
	}

# ── Cleanup ───────────────────────────────────────────────────────────────────

waitpid($writer_pid, 0) ;
kill 'TERM', $fzf_pid ;
waitpid($fzf_pid, 0) ;

my $summary = sprintf "DONE items=%d query='%s' indexing=%.1fs latency=%s",
	$opt_items, $opt_query, $idx_time, $latency ;
log_line($summary) ;
print "$summary\nFull output: $opt_log\n" ;
close $LOG ;
