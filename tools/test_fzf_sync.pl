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
# Watch it with:  tail -f /tmp/fzf_sync_test.log
#
# READING THE OUTPUT
# ------------------
# Test 1: "Indexing complete Ns" — time for fzf to see all items.
#
# Test 2: for each delay (0ms, 10ms, 50ms...) reports:
#   "filtered OK"     — GET returned correct filtered results
#   "SAME AS EMPTY"   — fzf hadn't processed the query yet (stale)
#   "TIMEOUT"         — fzf took longer than --timeout ms to respond
#
#   The SMALLEST delay showing "filtered OK" is the minimum the widget
#   must wait between POST and GET.  If 2000ms still shows "SAME AS EMPTY",
#   the widget's StatePoller timeout (2000ms) will always fail for this
#   dataset size and the StatePoller timeout_ms must be increased.
#
# Test 3: polls every 25ms, shows when matchCount changes from baseline.
#   "fzf search latency = Nms" is the key number.
#   If this exceeds StatePoller timeout_ms (2000ms default), the widget
#   silently discards every query result and the list never filters.

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

sub log_line { printf $LOG "[%.3f] %s\n", gettimeofday(), $_[0] }

# ── Pick a free port ──────────────────────────────────────────────────────────

if ($opt_port == 0)
	{
	my $s = IO::Socket::INET->new(Listen=>1, LocalAddr=>'127.0.0.1',
	                               LocalPort=>0, Proto=>'tcp', ReuseAddr=>1) ;
	$opt_port = $s->sockport() ; $s->close() ;
	}

log_line("START items=$opt_items query='$opt_query' timeout=${opt_timeout}ms port=$opt_port") ;
print "Running. Output → $opt_log\n(tail -f $opt_log in another terminal)\n" ;

# ── Launch fzf using a PTY (required — fzf needs a terminal for output) ───────

pipe(my $stdin_r, my $stdin_w) or die "pipe: $!" ;
my $pty = IO::Pty->new() ;

my $fzf_pid = fork() ;
die "fork: $!" unless defined $fzf_pid ;

if ($fzf_pid == 0)
	{
	$pty->make_slave_controlling_terminal() ;
	my $slave = $pty->slave() ;

	close $stdin_w ;
	POSIX::dup2(fileno($stdin_r), 0) ; close $stdin_r ;

	# Redirect fzf stdout/stderr to /dev/null — we only use its HTTP API
	open(my $null, '>', '/dev/null') or _exit(1) ;
	POSIX::dup2(fileno($null), 1) ;
	POSIX::dup2(fileno($null), 2) ;
	close $null ;
	close $slave ;

	exec('fzf', "--listen=$opt_port", '--no-sort') ;
	_exit(1) ;
	}

close $stdin_r ;

# ── Wait for fzf HTTP server ──────────────────────────────────────────────────

{
my $t0 = gettimeofday() ;
my $up = 0 ;
while (gettimeofday() - $t0 < 15)
	{
	my $s = IO::Socket::INET->new(PeerHost=>'127.0.0.1', PeerPort=>$opt_port,
	                               Proto=>'tcp', Timeout=>0.1) ;
	if ($s) { $s->close() ; $up = 1 ; last }
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

# ── Write items (forked child, so parent event loop is free) ─────────────────

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
my $sock = IO::Socket::INET->new(PeerHost=>'127.0.0.1', PeerPort=>$opt_port,
                                  Proto=>'tcp', Timeout=>$timeout_ms/1000) ;
return undef unless $sock ;
$sock->autoflush(1) ;
printf $sock "GET /?limit=%d HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", $limit ;
my ($body, $in) = ('', 0) ;
while (defined(my $l = $sock->getline()))
	{ if (!$in) { $in=1 if $l eq "\r\n" ; next } $body.=$l }
$sock->close() ;
my $mc = ($body =~ /"matchCount"\s*:\s*(\d+)/) ? $1 : undef ;
my $tc = ($body =~ /"totalCount"\s*:\s*(\d+)/) ? $1 : undef ;
my @idx = ($body =~ /"index"\s*:\s*(\d+)/g) ;
return { mc=>$mc//0, tc=>$tc//0, n=>scalar @idx } ;
}

sub send_query
{
my ($q) = @_ ;
my $sock = IO::Socket::INET->new(PeerHost=>'127.0.0.1', PeerPort=>$opt_port,
                                  Proto=>'tcp', Timeout=>5) ;
return unless $sock ;
$sock->autoflush(1) ;
my $body = "change-query($q)" ;
my $len  = length($body) ;
printf $sock "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
	$len, $body ;
eval { local $/ ; <$sock> } ;
$sock->close() ;
}

# ── Test 1: indexing progress ─────────────────────────────────────────────────

log_line("") ;
log_line("═══ Test 1: indexing — wait for totalCount to reach $opt_items ═══") ;

my $t_idx = gettimeofday() ;
my $indexed = 0 ;

for my $i (1..600)
	{
	my $s = get_state(1, 5000) ;
	log_line(sprintf "  poll %3d: tc=%-8d mc=%-8d", $i, $s->{tc}, $s->{mc}) ;
	if ($s->{tc} >= $opt_items) { $indexed=1 ; last }
	Time::HiRes::sleep(0.2) ;
	}

my $idx_time = gettimeofday() - $t_idx ;
log_line(sprintf "Indexing complete: %.3fs", $idx_time) ;

unless ($indexed)
	{
	log_line("ABORT: fzf did not index all items within timeout") ;
	kill 'TERM', $fzf_pid ; waitpid($fzf_pid,0) ;
	print "ABORT — see $opt_log\n" ; exit 1 ;
	}

# ── Test 2: delay between POST and GET ───────────────────────────────────────

log_line("") ;
log_line("═══ Test 2: minimum delay between POST change-query and GET ═══") ;

send_query('') ; Time::HiRes::sleep(0.3) ;
my $base = get_state(1, 5000)->{mc} ;
log_line("Baseline (empty query) mc = $base") ;
log_line(sprintf "%-8s %-8s %-8s %s", "delay_ms", "mc", "tc", "result") ;

for my $delay (0, 5, 10, 20, 50, 100, 200, 500, 1000, 2000)
	{
	send_query('') ; Time::HiRes::sleep(0.3) ;

	my $t0 = gettimeofday() ;
	send_query($opt_query) ;
	Time::HiRes::sleep($delay/1000) if $delay ;
	my $s = get_state($opt_limit, $opt_timeout) ;
	my $ms = int((gettimeofday()-$t0)*1000) ;

	my $result = !$s                  ? "TIMEOUT"
	           : $s->{mc} == 0        ? "EMPTY — query not processed yet"
	           : $s->{mc} == $base    ? "SAME AS EMPTY — stale result"
	           :                        sprintf "filtered OK  mc=%d  (%.1f%% of %d)",
	                                      $s->{mc}, 100*$s->{mc}/$opt_items, $opt_items ;

	log_line(sprintf "  delay=%-5dms  mc=%-7d  tc=%-7d  total=%4dms  %s",
		$delay, $s?$s->{mc}:0, $s?$s->{tc}:0, $ms, $result) ;
	}

# ── Test 3: latency until mc stabilises ──────────────────────────────────────

log_line("") ;
log_line("═══ Test 3: fzf search latency (poll every 25ms after POST) ═══") ;

send_query('') ; Time::HiRes::sleep(0.5) ;
my $bmc = get_state(1, 5000)->{mc} ;
log_line("Baseline mc = $bmc — sending query '$opt_query'...") ;

send_query($opt_query) ;
my $t0 = gettimeofday() ;
my ($prev, $stable, $first_ms) = ($bmc, 0, undef) ;

for my $p (1..200)
	{
	Time::HiRes::sleep(0.025) ;
	my $s   = get_state(1, $opt_timeout) ;
	my $mc  = $s ? $s->{mc} : 0 ;
	my $ms  = int((gettimeofday()-$t0)*1000) ;
	my $note = '' ;

	if ($mc != $prev)
		{
		$first_ms = $ms unless defined $first_ms ;
		$stable   = 0 ;
		$note     = sprintf " ← CHANGED %d→%d", $prev, $mc ;
		}
	else
		{
		$stable++ if defined $first_ms ;
		$note = " [stable $stable/3]" if $stable > 0 ;
		}

	log_line(sprintf "  poll %3d  %5dms  mc=%-7d%s", $p, $ms, $mc, $note) ;
	$prev = $mc ;
	last if $stable >= 3 || $ms > $opt_timeout ;
	}

my $latency = defined $first_ms ? "${first_ms}ms" : ">${opt_timeout}ms (TIMEOUT)" ;
log_line("") ;
log_line("fzf search latency for '$opt_query' with $opt_items items: $latency") ;
log_line("StatePoller timeout_ms should be > " . ($first_ms//?0*4:$opt_timeout))
	if defined $first_ms ;

# ── Cleanup ───────────────────────────────────────────────────────────────────

waitpid($writer_pid, 0) ;
kill 'TERM', $fzf_pid ; waitpid($fzf_pid, 0) ;

my $summary = "DONE items=$opt_items query='$opt_query' indexing=".sprintf("%.1fs",$idx_time)." latency=$latency" ;
log_line($summary) ;
print "$summary\nFull output: $opt_log\n" ;
close $LOG ;
