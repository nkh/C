# Lazy Fetch Design

## Architecture

Items are streamed to fzf in a forked child (`ItemWriter`) so the GTK main
loop is never blocked on startup.  fzf starts returning matches before all
items are loaded.

State is fetched from fzf's HTTP API asynchronously via `StatePoller`.  Each
HTTP request runs in a forked child; a Glib IO watch reads the response through
a pipe without blocking the main loop.

## Key state variables

| Variable | Meaning |
|---|---|
| `lazy_fetched` | Count of rows in `cached_matches` |
| `lazy_total_mc` | Total match count from last fzf response |
| `cached_matches` | Match objects currently held in Perl |
| `local_pos` | Current cursor row index into `cached_matches` |
| `_fetch_pending` | 1 while a fetch is in flight, 0 otherwise |

**Invariant**: `lazy_fetched == scalar @cached_matches` after every `_refresh_finish`.

## Refresh flow

```
_refresh()
  └─ get_state_async(limit=1)      [fork child → HTTP → pipe → IO watch]
       └─ callback fires when response arrives
            ├─ query_changed → get initial window, _refresh_finish
            └─ same query   → _fetch_more_async
                  ├─ cursor not near end → _refresh_finish
                  └─ cursor near end    → get_more_async(offset, page)
                        └─ callback → append rows, _refresh_finish

_refresh_finish()
  - clears _fetch_pending
  - updates cached_matches, local_pos
  - calls _update_list (GTK store rebuild)
  - calls _scroll_to to restore viewport
```

## Scroll trigger

`_navigate` detects when the cursor reaches `count - 1` (last loaded row) and
`lazy_total_mc > lazy_fetched`.  It sets `_fetch_pending = 1` and schedules a
1ms timer that calls `_refresh`.  `_fetch_pending` stays set until
`_refresh_finish` clears it, preventing duplicate fetches from rapid keypresses.

## StatePoller: skip-if-busy

`StatePoller` runs one HTTP request at a time in a forked child.  If `_request`
is called while a child is already running, the new request is silently dropped.
The bg_poll timer (100ms) and `_fetch_pending` together ensure the next
opportunity to fetch arrives quickly.

## Sequence diagram: scroll to last row

```
User              FzfWidget           StatePoller         fzf
  |                   |                    |               |
  | Down (at N-2)     |                    |               |
  |─────────────────>│                    |               |
  |                   | _navigate(+1)      |               |
  |                   | new_pos=N-1=last   |               |
  |                   | _fetch_pending=1   |               |
  |                   | timer 1ms          |               |
  |                   |                    |               |
  | [1ms later]       |                    |               |
  |                   | _refresh()         |               |
  |                   | get_state_async(1) |               |
  |                   |───────────────────>| fork child    |
  |                   |                    |──────────────>|
  | [keypresses queue while child runs — no blocking]      |
  |                   |                    |<── response ──|
  |                   |<── IO watch fires ─|               |
  |                   | _fetch_more_async  |               |
  |                   | get_more_async(N,page)             |
  |                   |───────────────────>| fork child    |
  |                   |                    |──────────────>|
  |                   |                    |<── response ──|
  |                   |<── IO watch fires ─|               |
  |                   | _refresh_finish    |               |
  |                   | _fetch_pending=0   |               |
  |                   | cached_matches grows               |
  |<── display N+page rows                |               |
```

## Why the old approach froze at ~950

Every `_refresh` previously called `get_state(N)` synchronously, where N grew
with each scroll step.  At 950 rows, `get_state(950)` fetched 950-item JSON
(~190 KB) and decoded it with `JSON::PP` (~500ms) — blocking the main loop each
poll cycle.  This caused keyboard events to queue, then flush all at once,
making the freeze reproducible at exactly the same row count.

The async `StatePoller` + skip-if-busy design eliminates all blocking.
