# Gtk3::FzfWidget Architecture

## Overview

The widget is a GTK3 Box subclass that wraps a background fzf process.
fzf does the fuzzy matching; the widget handles display, interaction,
and communication.

## Components

- `FzfWidget.pm` — the GTK3 widget. Owns the UI, local state cache,
  keybinding dispatch, markup rendering, and all callbacks.
- `Process.pm` — spawns and monitors the fzf child process. Uses
  IO::Pty to give fzf a controlling terminal (fzf requires isatty).
  Feeds items via a stdin pipe. Manages restart on crash.
- `Client.pm` — HTTP client talking to fzf's `--listen` port.
  GET fetches state and matches (paged at 400 per request). POST
  sends actions (change-query, down, up, toggle, select-all, etc.).
- `Layout.pm` — packs named widget slots (query, list, header) into
  a GTK Box in user-specified order.
- `Messages.pm` — all user-visible strings in one place.
- `fzfw` — command-line launcher; thin wrapper around the widget.

## Process lifecycle

fzf is started with `--listen=PORT` where PORT is OS-assigned by
binding a temporary socket. fzf reads items from stdin then closes
it. A Glib timer polls waitpid every 500ms to detect crashes without
blocking the GTK main loop (SIGCHLD is unreliable in GTK).

After `start_delay_ms` a Client is connected and the `on_ready`
callback fires. On crash, fzf is restarted up to 3 times before
`on_error` is called.

## Communication model

Every POST action syncs the fzf cursor or selection state. GET
fetches the full match list and counts. To keep UI responsive:

- Navigation (Down/Up/Tab) — POST only, update display from local
  cache. No GET.
- Query change — POST new query, then GET to refresh match list.
- Background poll — GET every poll_ms only when match/total counts
  change (detects large dataset indexing completing).
- Ctrl+A / Ctrl+D — POST then GET (bulk selection change).

## Local state cache

`cached_matches`, `local_pos`, `local_selected` mirror fzf's state.
Navigation and toggle operate on the cache; the store is updated by
redrawing only the two affected rows. Full store rebuild happens only
when the match list changes.

## Markup pipeline

Each item goes through: tab expansion (with position remapping) →
ANSI parsing (if ansi=1) → transform_fn → fuzzy position highlight
spans → cursor/stripe background wrap → Pango markup string stored
in column 0 of the ListStore.

## Image pipeline

`image_fn` is called for all rows after each full refresh. If any
row returns a pixbuf, the pixbuf column becomes visible and reserves
fixed width for all rows. Images are stored in ListStore column 4.

## Debounce

`_on_entry_changed` starts a Glib timer of `_debounce_ms()` ms
before calling `_send_query`. Each keystroke resets the timer.
Debounce time is looked up from a configurable table indexed by
total item count.

## Theming

Four built-in themes define all color keys. User `colors` hashref
is merged on top (user wins per key). CSS is built from merged
colors and loaded via `add_provider_for_screen` scoped to instance
CSS names (`#fzf-list-N`, `#fzf-wb-N`, etc.) to prevent bleed.
Cursor and stripe backgrounds bypass CSS — they are embedded in
Pango markup spans which always take precedence.
