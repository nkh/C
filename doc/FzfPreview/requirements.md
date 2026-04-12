# Gtk3::FzfPreview Requirements

## What it does

You give it a list of items and a way to map each item to a file. It shows
a fuzzy-search list on the left and a file preview on the right. As you
move through the list, the preview updates automatically. You can configure
how much horizontal space each side takes, whether a drag handle is shown,
and keyboard shortcuts to hide either side entirely.

## Layout

- Horizontal box containing FzfWidget on the left and PreviewPane on the right
- Default split: 50% each when average item length exceeds 40 characters; 30% fzf / 70% preview for shorter items
- User sets explicit fraction via `fzf_width` (0.0–1.0)
- When `resizable => 1`, a GTK HPaned grip/handle appears between the two panes; the user drags it to resize
- When one pane is hidden, the other expands to fill the full width

## Item-to-file resolution

Resolution is attempted in this order:

- Hashref `item_to_file => { text => path }` — direct lookup by item text
- Coderef `item_to_file => sub { ($text, $idx) -> $path }` — computed path
- If neither is provided and the item text is a readable file or directory, it is used directly
- If none of the above resolves to a path, no preview is shown for that item

## Preview update

- Fires whenever the highlighted item changes via navigation, Tab toggle, or click
- Calls `PreviewPane::load($path, $extra)` where `$extra` comes from the `on_preview` callback if set
- The user-supplied `on_selection_change` callback is called after the preview update

## Visibility toggles

- User-configurable key bindings (`hide_fzf_key`, `hide_preview_key`)
- Default: Ctrl+H hides/shows the fzf list; Ctrl+P hides/shows the preview
- When a pane is hidden it is entirely invisible; the other expands to fill the space
- Toggling a hidden pane restores it to its previous size

## Callbacks

- `on_confirm($self, $selections, $query)` — forwarded from FzfWidget confirm
- `on_cancel($self)` — forwarded from FzfWidget cancel
- `on_preview($self, $path, $text, $index)` — fires before each preview load; return `($path, $extra_text)` to override the path or add a label above/below the content; returning nothing uses the resolved path with no extra text

## Configuration

All FzfWidget config keys pass through under the `fzf` subkey.
All PreviewPane config keys pass through under the `preview` subkey.

Top-level config keys:

- `fzf_width` (float 0.0–1.0, default auto-computed)
- `resizable` (bool, default 0)
- `show_fzf` (bool, default 1)
- `show_preview` (bool, default 1)
- `hide_fzf_key` (string, default `'ctrl+h'`)
- `hide_preview_key` (string, default `'ctrl+p'`)
- `on_confirm`, `on_cancel`, `on_preview` (callbacks)

## Public methods

- `fzf_widget()` — returns the embedded `Gtk3::FzfWidget` for direct access
- `preview_pane()` — returns the embedded `Gtk3::PreviewPane` for direct access

## Dependencies

- `Gtk3::FzfWidget` >= 0.01
- `Gtk3::PreviewPane` >= 0.01
- Gtk3, Glib, File::Basename, List::Util
