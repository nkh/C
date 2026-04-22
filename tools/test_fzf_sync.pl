#!/usr/bin/perl

# test_fzf_sync.pl
#
# PURPOSE
# -------
# When the user types a query in Gtk3::FzfWidget with a large dataset,
# the query change is sent to fzf via HTTP POST (change-query), then the
# widget immediately does an HTTP GET to fetch the filtered results.
#
# The problem: fzf may not have finished computing the new match list by
# the time the GET arrives.  If the GET is too early, fzf returns stale
# results (the old match list) and the display does not update.
#
# This script quantifies exactly:
#   A) How long fzf takes to index N items (totalCount reaches N)
#   B) After sending change-query, how long before the GET returns the
#      correct filtered result — tested at delays of 0ms, 10ms, 50ms, etc.
#   C) The minimum polling interval needed to detect when fzf has
#      finished recomputing results for a given query + item count.
#
# HOW TO RUN
# ----------
# Basic (10k items, query 'abc'):
#   perl test_fzf_sync.pl
#
# Larger dataset:
#   perl test_fzf_sync.pl --items 100000 --query xyz
#   perl test_fzf_sync.pl --items 500000 --query ent --timeout 30000
#
# All output goes to the log file (default: /tmp/fzf_sync_test.log).
# NOTHING is printed to the terminal except the final summary line.
#   tail -f /tmp/fzf_sync_test.log    # in another terminal while running
#
# WHAT TO DO WITH THE OUTPUT
# --------------------------
# Look for these key values in the log:
#
# 1. "Indexing complete" — tells you how long fzf takes to index N items.
#    If this is slow, the widget's load timer poll interval may need tuning.
#
# 2. Test 2 table — for each delay value (0ms, 10ms, ...) you see whether
#    the GET returned "filtered OK" or "EMPTY/unfiltered".
#    The SMALLEST delay that consistently returns "filtered OK" is the
#    minimum wait the widget must implement between POST and GET.
#    If even 1000ms shows "unfiltered", fzf is still computing at that point
#    and the StatePoller timeout (currently 2000ms) will fail.
#
# 3. Test 3 — shows per-poll whether mc has changed from baseline.
#    The elapsed time when mc first changes and then stabilises tells you
#    the true fzf search latency for this query + item count combination.
#    Compare this against the StatePoller timeout (2000ms default).
#    If the latency exceeds 2000ms, increase StatePoller timeout_ms.
#
# INTERPRETING RESULTS
# --------------------
# If Test 2 shows "unfiltered" even at 500ms delay for 500k items:
#   → fzf takes > 500ms to compute matches
#   → The widget's post_sync + immediate get_state_async will always miss
#   → Solution: PerlMatcherBackend (no fzf latency) or increase timeout
#
# If Test 3 shows mc stabilises at 50ms:
#   → A 100ms delay in SocketBackend::query_async would be sufficient
#   → But this varies by CPU, dataset, and query

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
my $opt_log     = '/tmp/fzf_sync_test.log' ;

GetOptions(
	'items=i'   => \$opt_items,
	'query=s'   => \$opt_query,
	'timeout=i' => \$opt_timeout,
	'port=i'    => \$opt_port,
	'limit=i'   => \$opt_limit,
	'log=s'     => \$opt_log,
	) or die "Usage: $0 [--items N] [--query STR] [--timeout MS] [--log FILE]\n" ;

# ── Open log file — all output goes here, nothing to STDOUT/STDERR ───────────

open(my $LOG, '>', $opt_log) or die "Cannot open log $opt_log: $!" ;
$LOG->autoflush(1) ;

sub log_line
{
my ($msg) = @_ ;
my ($s, $u) = gettimeofday() ;
printf $LOG "[%.3f] %s\n", $s + $u/1e6, $msg ;
}

# ── Find a free port ──────────────────────────────────────────────────────────

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

log_line("START items=$opt_items query='$opt_query' timeout=${opt_timeout}ms port=$opt_port limit=$opt_limit log=$opt_log") ;
print "Running. Output → $opt_log\nTail with: tail -f $opt_log\n" ;

# ── Start fzf ─────────────────────────────────────────────────────────────────
# fzf is a TUI app that writes directly to /dev/tty even when stdout is
# redirected.  --no-tty prevents this.  Redirect all fzf output to /dev/null.

pipe(my $stdin_r, my $stdin_w) or die "pipe: $!" ;

my $fzf_pid = fork() ;
die "fork fzf: $!" unless defined $fzf_pid ;

if ($fzf_pid == 0)
	{
	close $stdin_w ;
	open(STDIN,  '<&', $stdin_r) or _exit(1) ;
	open(STDOUT, '>',  '/dev/null') ;
	open(STDERR, '>',  '/dev/null') ;
	close $stdin_r ;
	exec('fzf', "--listen=$opt_port", '--no-sort', '--no-tty') ;
	_exit(1) ;
	}

close $stdin_r ;

# Wait for fzf HTTP server to accept connections
{
my $t0 = gettimeofday() ;
my $up = 0 ;
while (gettimeofday() - $t0 < 10)
	{
	my $s = IO::Socket::INET->new(PeerHost => '127.0.0.1', PeerPort => $opt_port,
	                               Proto => 'tcp', Timeout => 0.1) ;
	if ($s) { $s->close() ; $up = 1 ; last }
	Time::HiRes::sleep(0.05) ;
	}
die "fzf did not start in 10s\n" unless $up ;
log_line(sprintf "fzf ready in %.3fs", gettimeofday() - $t0) ;
}

# ── Write items to fzf stdin in a child ───────────────────────────────────────

my $writer_pid = fork() ;
die "fork writer: $!" unless defined $writer_pid ;

if ($writer_pid == 0)
	{
	# All output in the child goes to the log, not stderr
	my $t = gettimeofday() ;
	for my $i (1 .. $opt_items)
		{
		# Items: "entry_000001_abcdefgh_xxxxxxxx"
		# Most contain 'abc' somewhere, making --query abc match ~all items.
		# Use a query that matches a subset for meaningful filter tests.
		printf $stdin_w "entry_%06d_abcdefgh_%s\n", $i,
			join('', map { ('a'..'z')[int(rand(26))] } 1..8) ;
		}
	close $stdin_w ;
	_exit(0) ;
	}

close $stdin_w ;

# ── HTTP helpers ──────────────────────────────────────────────────────────────

sub http_get
{
my ($path, $timeout_ms) = @_ ;
my $sock = IO::Socket::INET->new(
	PeerHost => '127.0.0.1',
	PeerPort => $opt_port,
	Proto    => 'tcp',
	Timeout  => $timeout_ms / 1000,
	) ;
return (undef, $timeout_ms / 1000) unless $sock ;
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
my ($body, $timeout_ms) = @_ ;
$timeout_ms //= 5000 ;
my $sock = IO::Socket::INET->new(
	PeerHost => '127.0.0.1',
	PeerPort => $opt_port,
	Proto    => 'tcp',
	Timeout  => $timeout_ms / 1000,
	) ;
return 0 unless $sock ;
$sock->autoflush(1) ;
my $len = length($body) ;
print $sock "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: $len\r\nConnection: close\r\n\r\n$body" ;
eval { local $/ ; <$sock> } ;
$sock->close() ;
return 1 ;
}

sub parse_state
{
my ($json) = @_ ;
return { mc => 0, tc => 0, n => 0 } unless $json ;
my $mc = ($json =~ /"matchCount"\s*:\s*(\d+)/) ? $1 : 0 ;
my $tc = ($json =~ /"totalCount"\s*:\s*(\d+)/) ? $1 : 0 ;
my @idx = ($json =~ /"index"\s*:\s*(\d+)/g) ;
return { mc => $mc, tc => $tc, n => scalar @idx } ;
}

# ── Test 1: wait for indexing to complete ─────────────────────────────────────

log_line("") ;
log_line("═══ Test 1: indexing progress ═══") ;
log_line(sprintf "Feeding %d items to fzf, polling until totalCount reaches %d",
	$opt_items, $opt_items) ;

my $t_index = gettimeofday() ;
my $indexed = 0 ;

for my $i (1..600)
	{
	my ($resp, $elapsed) = http_get('/?limit=1', $opt_timeout) ;
	my $s = parse_state($resp) ;
	log_line(sprintf "  poll %3d: tc=%-8d mc=%-8d get_time=%.3fs", $i, $s->{tc}, $s->{mc}, $elapsed) ;

	if ($s->{tc} >= $opt_items)
		{
		$indexed = 1 ;
		last ;
		}

	Time::HiRes::sleep(0.2) ;
	}

my $index_time = gettimeofday() - $t_index ;
log_line(sprintf "Indexing complete: %.3fs indexed=%d", $index_time, $indexed) ;

unless ($indexed)
	{
	log_line("FAIL: fzf did not finish indexing within timeout") ;
	kill 'TERM', $fzf_pid ;
	waitpid($fzf_pid, 0) ;
	print "FAIL: indexing timeout. See $opt_log\n" ;
	exit 1 ;
	}

# ── Test 2: delay between POST change-query and GET ──────────────────────────

log_line("") ;
log_line("═══ Test 2: minimum delay between POST change-query and GET ═══") ;
log_line("For each delay value: reset query → POST change-query(QUERY) → wait delay → GET") ;
log_line("'filtered OK' means GET returned a result different from the empty-query baseline") ;
log_line("'SAME AS EMPTY' means fzf had not yet processed the query — stale result returned") ;
log_line(sprintf "%-10s %-8s %-8s %-10s %s", "delay_ms", "mc", "tc", "total_ms", "result") ;

# Establish baseline: mc with empty query = total items
http_post("change-query()") ;
Time::HiRes::sleep(0.5) ;
my ($r_base) = http_get('/?limit=1', $opt_timeout) ;
my $baseline_mc = parse_state($r_base)->{mc} ;
log_line(sprintf "Baseline empty-query mc = %d", $baseline_mc) ;

for my $delay_ms (0, 5, 10, 20, 50, 100, 200, 500, 1000, 2000)
	{
	http_post("change-query()") ;
	Time::HiRes::sleep(0.3) ;   # let fzf reset

	my $t0 = gettimeofday() ;
	http_post("change-query($opt_query)") ;
	Time::HiRes::sleep($delay_ms / 1000) if $delay_ms > 0 ;
	my ($resp) = http_get("/?limit=$opt_limit", $opt_timeout) ;
	my $total_ms = int((gettimeofday() - $t0) * 1000) ;
	my $s = parse_state($resp) ;

	my $result = !defined($resp)    ? 'TIMEOUT — no response'
	           : $s->{mc} == 0      ? 'EMPTY — fzf returned 0 matches'
	           : $s->{mc} == $baseline_mc ? 'SAME AS EMPTY — query not applied yet'
	           :                       sprintf 'filtered OK (mc=%d, %.1f%% of total)',
	                                     $s->{mc}, 100*$s->{mc}/$opt_items ;

	log_line(sprintf "  delay=%-5dms  mc=%-8d  tc=%-8d  total=%-6dms  %s",
		$delay_ms, $s->{mc}, $s->{tc}, $total_ms, $result) ;
	}

# ── Test 3: poll until mc stabilises ─────────────────────────────────────────

log_line("") ;
log_line("═══ Test 3: how long until match count stabilises after change-query ═══") ;
log_line("Polls every 25ms after POST. Shows when fzf finishes recomputing.") ;
log_line("The elapsed_ms when '[STABLE]' first appears is the fzf search latency.") ;
log_line("If this exceeds the StatePoller timeout (2000ms), the widget will miss the result.") ;

http_post("change-query()") ;
Time::HiRes::sleep(0.5) ;
my ($rb) = http_get('/?limit=1', $opt_timeout) ;
my $bmc = parse_state($rb)->{mc} ;
log_line(sprintf "Baseline mc (empty query) = %d", $bmc) ;
log_line("Sending change-query($opt_query)...") ;

http_post("change-query($opt_query)") ;
my $t_post = gettimeofday() ;
my ($prev_mc, $stable_count, $first_change_ms) = ($bmc, 0, undef) ;

for my $p (1..200)
	{
	Time::HiRes::sleep(0.025) ;
	my ($resp) = http_get('/?limit=1', $opt_timeout) ;
	my $s = parse_state($resp) ;
	my $mc = $s->{mc} ;
	my $elapsed_ms = int((gettimeofday() - $t_post) * 1000) ;
	my $flag = '' ;

	if ($mc != $prev_mc)
		{
		$first_change_ms //= $elapsed_ms ;
		$stable_count = 0 ;
		$flag = sprintf " ← CHANGED (%d→%d)", $prev_mc, $mc ;
		}
	else
		{
		$stable_count++ if defined $first_change_ms ;
		$flag = " [STABLE $stable_count/3]" if $stable_count > 0 ;
		}

	log_line(sprintf "  poll %3d  elapsed=%5dms  mc=%d%s", $p, $elapsed_ms, $mc, $flag) ;
	$prev_mc = $mc ;

	last if $stable_count >= 3 ;
	last if $elapsed_ms > $opt_timeout ;
	}

if (defined $first_change_ms)
	{
	log_line(sprintf "RESULT: fzf returned new results after %dms for query='%s' with %d items",
		$first_change_ms, $opt_query, $opt_items) ;
	log_line(sprintf "        StatePoller timeout should be at least %dms (current: 2000ms)",
		$first_change_ms * 3) ;
	}
else
	{
	log_line("RESULT: mc never changed — fzf did not return filtered results within timeout") ;
	log_line("        This means fzf search latency > ${opt_timeout}ms for this dataset") ;
	}

# ── Cleanup ───────────────────────────────────────────────────────────────────

waitpid($writer_pid, 0) ;
kill 'TERM', $fzf_pid ;
waitpid($fzf_pid, 0) ;

my $summary = sprintf "DONE items=%d query='%s' indexing=%.1fs fzf_search_latency=%s",
	$opt_items,
	$opt_query,
	$index_time,
	defined $first_change_ms ? "${first_change_ms}ms" : "TIMEOUT" ;

log_line($summary) ;
print "$summary\nFull results: $opt_log\n" ;
close $LOG ;
