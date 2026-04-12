# Gtk3::PreviewPane Requirements

## What it does

You give the pane a file path and it shows the contents. Text files are
displayed in a scrollable editor view with vim-like keyboard navigation.
Images are displayed with zoom and fit controls. An optional label above
or below the content shows extra information you provide. A status bar
at the bottom shows the file name and either the line count (text) or
the image dimensions and zoom level (image).

## Display modes

- Text mode — activated for file extensions: pl pm py rb sh bash zsh js ts c h cpp rs go java txt md rst log conf ini yaml yml toml json xml html css, and any unrecognised extension
- Image mode — activated for: png jpg jpeg gif bmp webp tiff tif svg ico
- Mode is detected automatically from the file extension when `load()` is called

## Text display

- GtkTextView in read-only, no-cursor mode
- Horizontal and vertical scrollbars
- Monospace font by default, configurable family and size
- Files read with UTF-8 encoding
- Scroll position reset to top on each new file load

## Text navigation

- Arrow keys, Page Up/Down, Home/End via standard scrolled window
- Additional vim-like bindings active when pane has focus: j/k (scroll one line), Ctrl+d/u (half page), g (top), G (bottom)
- All bindings configurable via `keybindings` hashref

## Image display

- GtkDrawingArea renders the image using cairo
- Image resampled with bilinear filtering for quality
- Fit mode: fit to height (default), fit to width, or none
- When fit mode is active, image is re-fitted automatically on window resize
- Zoom level displayed as percentage in status bar

## Image navigation

- `+` / `=` — zoom in by configurable factor (default 130%)
- `-` — zoom out by the same factor
- `0` — reset to 100%
- `f` — fit to height
- Minimum zoom clamped to 1% to prevent invisible image
- All zoom keys active only when image mode is current

## Extra label

- Fixed `Gtk3::Label` widget, hidden when no text is set
- Position configurable: `top` (above content) or `bottom` (below content)
- Updated by passing second argument to `load($path, $extra)` or calling `set_extra_text($text)` / `clear_extra_text()`
- Supports plain text with newlines — no Pango markup

## Status bar

- Single `Gtk3::Label` at the bottom
- Text mode: `filename — N lines`
- Image mode: `filename — WxH — Z%`
- Hidden via `show_status => 0`
- Colors follow the theme

## Themes

- `dark` — dark background, light text
- `light` — light background, dark text
- `normal` — uses GTK theme defaults
- Colors applied via scoped CSS providers and Pango font descriptions

## Configuration

- `theme` (string, default `'dark'`)
- `font_family` (string, default `'Monospace'`)
- `font_size` (integer, default 13)
- `zoom_factor` (float, default 1.3)
- `fit_mode` (string: `'height'`, `'width'`, `'none'`, default `'height'`)
- `extra_position` (string: `'top'` or `'bottom'`, default `'top'`)
- `show_status` (bool, default 1)
- `keybindings` (hashref, merged over defaults)

## Public methods

- `load($path)` — load a file, detect mode from extension
- `load($path, $extra)` — load a file and show extra text in the label
- `set_extra_text($text)` — update the extra label without reloading the file
- `clear_extra_text()` — hide the extra label
- `get_current_path()` — returns the currently loaded path
- `get_current_mode()` — returns `'text'`, `'image'`, or `undef`
- `get_zoom_level()` — returns current zoom multiplier

## Embedding

- `Gtk3::Box` subclass — pack into any container
- No dependency on `Gtk3::FzfWidget` — fully standalone
- Designed to work alongside FzfWidget via `Gtk3::FzfPreview`

## Dependencies

- Gtk3, Glib, File::Basename, Encode, POSIX
