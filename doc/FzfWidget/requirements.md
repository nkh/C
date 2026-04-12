# Gtk3::FzfWidget Requirements

## What it does for you

You give the widget a list of items — filenames, commands, records,
anything — and it gives your user a fast, keyboard-driven fuzzy
search over that list. The user types a few characters, the list
narrows in real time, they press Return or click OK, and you get
back what they chose. The widget handles all the fuzzy matching,
display, scrolling, and keyboard shortcuts so you don't have to.

## Items

You can pass items as a plain array or as a function that returns
one. When fzf finishes loading a large list, the widget detects
the change and refreshes automatically without you having to do
anything. You can replace the item list at any time with
`set_items()` or `reload_items()`.

## Filtering

Fuzzy matching is done by fzf running in the background. The widget
talks to fzf over HTTP. You can switch between fuzzy (default),
exact, and prefix matching via `search_mode`. The widget works with
lists of any size — it fetches results in pages of 400 so even very
large lists don't block the UI.

## Display

The list shows matched characters highlighted in a configurable
color. The current row is highlighted with a distinct background
that always wins over the theme so it is always visible. Tabs in
item text are expanded to configurable tab stops so columns line up.
ANSI color codes in items are rendered as colors when `ansi` is on.
A transform function can rewrite how items look without changing
what gets returned on confirm. An image function can provide a
pixbuf for each row, displayed as a thumbnail column before the text.
Alternating row colors (striping) can be set with any number of colors.

## Layout

The search entry, item list, and optional header label can be placed
in any order you choose. The header shows a static string above (or
anywhere in) the list — useful for column headings or a title.
An info area below the list displays text returned by an `on_hover`
callback when the user moves the mouse over a row, useful for
previewing item details without leaving the widget.

## Selection

In single mode, the widget confirms one item. In multi mode the user
Tabs through items to toggle selection on or off, and confirms all
selected items at once. Ctrl+A selects everything visible,
Ctrl+D clears all selections. You can pre-select items by passing
their indices in `initial_selection`. You are notified of each
toggle via `on_selection_change` so you can update other parts of
your UI in real time.

## Keyboard

The full keyboard map is configurable. Every action — confirm,
cancel, focus the search entry, clear the query, navigate, toggle —
can be rebound to any key combination. The defaults follow common
conventions: Return and Ctrl+O confirm, Escape cancels, Ctrl+Q
focuses the entry, Ctrl+U clears it. Page Up/Down move ten rows at
a time; Ctrl+Home/End jump to the ends. Wrapping at the list edges
is optional.

## Appearance

Four built-in themes — normal, dark, solarized-dark, solarized-light
— set a consistent color palette including the border. Every color
can be overridden individually. The header and info area have
independent foreground and background colors that follow the theme
or can be set separately. Font family and size are configurable.
The window size defaults to half the screen width and full height
and can be fixed, constrained, or set to full screen. The border
around the widget shows in the theme's border color when
`border_width` is greater than zero.

## Status bar

The match counter sits in the bottom bar alongside the buttons. Its
format is configurable — you can pass a sprintf string or a function
that receives the match count, total count, and selected count and
returns any string you want. The counter and the buttons can each be
hidden independently.

## Callbacks

You wire in your logic through callbacks:

- `on_confirm` — receives the selected items and the current query
  when the user confirms.
- `on_cancel` — fires when the user closes without confirming.
- `on_error` — fires if fzf cannot be started or crashes repeatedly.
- `on_query_change` — fires on every query change, useful for
  updating other UI elements.
- `on_selection_change` — fires when the selected set changes in
  multi mode.
- `on_hover` — fires when the mouse moves over a row; return a
  string to display in the info area.
- `on_ready` — fires when fzf has finished loading all items.

## Programmatic control

You can change the search query from code with `set_query()`. You
can freeze the widget to pause all updates while you make bulk
changes, then unfreeze to refresh. `get_match_count()` and
`get_total_count()` give you the current counts. `get_selection()`
and `get_filtered_list()` let you inspect state without waiting for
a confirm.

## fzfw command

`fzfw` is a ready-to-use command that wraps the widget. Pipe
anything into it and it returns what the user picks, one item per
line. Nearly every widget option is available as a command-line
flag. It reads NUL-delimited input with `--null`, prints the item
index instead of text with `--output-index`, prints the query with
`--print-query`, and accepts `--header` for a column label.

## What it needs

fzf >= 0.65.0 must be on PATH. Perl modules required:
Gtk3, Glib, IO::Pty, IO::Socket::INET, JSON::PP.
