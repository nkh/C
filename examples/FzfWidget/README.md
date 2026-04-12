# Gtk3::FzfWidget Examples

All examples use `use lib '../lib'` and must be run from the `examples/` directory.

## Synopsis

```perl
use Gtk3 -init ;
use Gtk3::FzfWidget ;

Gtk3->init() ;

my $win = Gtk3::Window->new('toplevel') ;
$win->signal_connect(destroy => sub { Gtk3->main_quit() }) ;

my $widget = Gtk3::FzfWidget->new(
    items  => [qw(apple banana cherry)],
    config =>
        {
        theme      => 'dark',
        on_confirm => sub
            {
            my ($w, $sel, $query) = @_ ;
            print "$_->[0]\n" for @$sel ;
            Gtk3->main_quit() ;
            },
        on_cancel  => sub { Gtk3->main_quit() },
        },
    ) ;

$win->add($widget) ;
$win->show_all() ;
Gtk3->main() ;
```

## Examples

**00_all_options_template.pl**                                           - Every config option listed with detailed comments. Use as a reference when building a new widget.
**01_minimal_single_select.pl**                                          - Simplest possible usage with default theme.
**02_dark_theme_custom_cursor.pl**                                       - Dark theme with one color key overridden.
**03_multiselect_solarized.pl** - Multi-select with solarized            - dark and `on_selection_change`.
**04_header_query_below.pl**                                             - Header above list, query entry below. Header and list fonts must match for alignment.
**05_ansi_colors.pl**                                                    - ANSI SGR escape codes rendered as colors.
**06_fixed_window_border.pl**                                            - Fixed 800×500 window with border.
**07_coderef_items.pl**                                                  - Items from a coderef (lazy loading).
**08_initial_query_selection.pl** - Pre-filled query and pre             - selected items on startup.
**09_tab_aligned_header.pl**                                             - Computed column widths for perfect alignment across all rows.
**10_custom_status_format.pl**                                           - Custom match counter string via `status_format` coderef.
**11_hover_info_area.pl**                                                - File metadata shown in the info area on mouse hover.
**12_row_striping.pl**                                                   - Three alternating row background colors.
**13_images_thumbnails.pl**                                              - Thumbnails for images, colored squares for other types, hover file details. Pass a directory as argument.
**14_transform_fn.pl**                                                   - Display text rewritten without affecting the confirmed value.
**15_custom_keybindings.pl** - Remapped confirm, cancel, and clear       - query keys.
**16_freeze_unfreeze.pl**                                                - Bulk item replace using freeze/unfreeze.
**17_exact_wrap_cursor.pl**                                              - Exact search mode with cursor wrapping.
**18_no_buttons_keyboard_only.pl** - Buttons and status hidden; keyboard - only interface.
**19_on_ready_callback.pl**                                              - `on_ready` fires when fzf finishes loading.
**20_output_index.pl**                                                   - Prints the original item index on confirm.
**21_selection_change.pl**                                               - Full `on_selection_change` signature with changed item details.
**22_embedded_in_layout.pl**                                             - Widget packed as a sidebar inside a larger GTK layout.
**23_custom_position_fn.pl** - Custom `position_fn` overrides the built  - in fuzzy highlighter.
**24_multi_click_toggle.pl**                                             - Click anywhere on a row to toggle it in multi mode.
**25_debounce_table.pl**                                                 - Custom debounce table tuned for large item sets.
**26_solarized_light.pl**                                                - Solarized light theme with one override.
**27_get_match_count.pl**                                                - `get_match_count()` and `get_total_count()` polled externally.
**28_set_query_programmatic.pl**                                         - `set_query()` driven by a Glib timer.
**29_status_format_fn.pl**                                               - Status coderef shows selection count only when non - zero.
**30_print_query_output.pl**                                             - `on_confirm` prints query then selected items.
**31_wrap_and_page.pl**                                                  - Cursor wrap with Page Up/Down and Ctrl+Home/End navigation.
**32_multi_select_all.pl** - Ctrl+A / Ctrl+D to bulk                     - select and deselect.
**33_reload_items.pl**                                                   - `reload_items()` replaces the list while the widget runs.
**text_and_images.pl**                                                   - Full file browser with images, type squares, and hover details.

