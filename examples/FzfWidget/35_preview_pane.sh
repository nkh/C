#!/usr/bin/env bash

# fzfw previewer script: inspect any file and return displayable content.
#
# Arguments supplied by fzfw via placeholder expansion:
#   $1  item text (the file path)
#   $2  original item index
#   $3  1 if item is selected, 0 otherwise
#   $4  current query string
#   $5  preview pane width in pixels
#   $6  preview pane height in pixels
#
# Output protocol:
#   First line must be one of: TEXT:  IMAGE:/path  FILE:/path
#   Optional CACHE: or NOCACHE: line before or after the content-type line.
#   For TEXT: all remaining stdout is the content to display.

ITEM="$1"
INDEX="$2"
SELECTED="$3"
QUERY="$4"
WIDTH="$5"
HEIGHT="$6"

if [ ! -e "$ITEM" ] ; then
    echo "TEXT:"
    echo "No such file or directory: $ITEM"
    exit 0
fi

EXT="${ITEM##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

case "$EXT_LOWER" in
    png|jpg|jpeg|gif|bmp|webp|tiff|tif|svg|ico)
        # Return the image path directly for display
        echo "IMAGE:$ITEM"
        ;;

    pdf)
        # Extract first page as text using pdftotext if available
        if command -v pdftotext &>/dev/null ; then
            echo "TEXT:"
            pdftotext -l 1 "$ITEM" - 2>/dev/null || echo "(cannot extract text from PDF)"
        else
            echo "TEXT:"
            echo "PDF file: $ITEM"
            echo "(install pdftotext for content preview)"
        fi
        ;;

    *)
        # Text file — show content with file info header
        echo "TEXT:"
        LINES=$(wc -l < "$ITEM" 2>/dev/null || echo '?')
        SIZE=$(wc -c < "$ITEM" 2>/dev/null || echo '?')
        echo "File  : $ITEM"
        echo "Index : $INDEX  |  Selected: $SELECTED  |  Query: $QUERY"
        echo "Lines : $LINES  |  Size: $SIZE bytes"
        echo "---"
        # Limit output to 500 lines to avoid flooding the preview pane
        head -500 "$ITEM"
        ;;
esac

exit 0
