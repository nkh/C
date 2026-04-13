# Lazy Fetch / Filter Design

## Architecture

Items are loaded once into a `Gtk3::ListStore` at startup — one row per item,
never deleted. A `Gtk3::TreeModelFilter` sits between the store and the
`TreeView`. Visibility is controlled by `_visible_set` (a Perl hash of matching
original indices). The `visible-func` callback does a hash lookup for each row;
GTK calls it only during `refilter()`.

## Backend abstraction

`FzfBackend` defines the interface:

- `query_async($query, $limit, $cb)` — filter by query, return first $limit matching indices
- `fetch_async($limit, $cb)` — fetch more matches for the current query
- `total_count()` / `match_count()`
- `stop()`

Two implementations:

- `SocketBackend` — wraps `Process` + `StatePoller`, talks to real fzf over HTTP
- `MockBackend` — in-process substring filter, no forks, no sockets, for debugging

Enable `MockBackend` by passing `backend => MockBackend->new(items => \@items)` to `FzfWidget::new`.

## Key state

| Field | Meaning |
|---|---|
| `_all_items` | arrayref of all item strings; index = original item index |
| `_match_indices` | ordered arrayref of matching original indices (fetched window) |
| `_visible_set` | hash `{ index => 1 }` read by visible-func |
| `_match_count` | total matches for current query (may exceed `_match_indices` length) |
| `_total_count` | total items indexed by backend |
| `_prefetch_at` | trigger prefetch when `local_pos >= _prefetch_at` |
| `_fetch_in_flight` | 1 while `fetch_async` is pending |
| `prefetch_buffer` | configurable (default 100); items fetched ahead of display end |

`local_pos` is a row index into `_match_indices` (filter-model space).
Store row N corresponds to `_all_items[N]` (original index = store row number).

## Query change flow

```
user types → debounce → _send_query()
  → _query_backend($query)
    → backend->query_async($query, prefetch_buffer*2, cb)
      → cb: _apply_query_result(\@matches, $mc, $tc)
        - _match_indices = [map {$_->{index}} @matches]
        - _visible_set   = {map {$_ => 1} @_match_indices}
        - local_pos = 0
        - _filter_model->refilter()
        - _rebuild_visible_markup()
        - _update_status_label()
```

No timers started. Done.

## Scroll flow

```
_navigate($delta)
  - update local_pos
  - _redraw_cursor(old, new)   — 2 store->set calls
  - _scroll_to(new, old)
  - if local_pos >= _prefetch_at AND _match_indices < _match_count:
      _prefetch_more()
  - if at last row AND fetch in flight:
      pump Glib::MainContext->iteration(0) up to 500ms
```

`_prefetch_more()`:
```
  _fetch_in_flight = 1
  backend->fetch_async(current + prefetch_buffer, cb)
    → cb: append new indices to _match_indices and _visible_set
          _filter_model->refilter()
          _fetch_in_flight = 0
```

## Timers

The only timer is `_load_timer`, which fires every `poll_ms` until
`backend->total_count() == scalar(@_all_items)` (all items indexed). Once that
condition is met the timer removes itself. With `MockBackend`, items are
available immediately so the timer fires once and stops.

No other timers run. There is no `bg_poll`, no `_reset_bg_poll`, no fetch
timer. When the user is idle (no query change, no scrolling near the end of
the window), nothing runs.

## Logging

Set `FZFW_DEBUG=1` to enable. Set `FZFW_LOG=/tmp/fzfw.log` to also write to
a file. Prefixes: `WIDGET:`, `BACKEND:SOCKET:`, `BACKEND:MOCK:`, `POLLER:`.
