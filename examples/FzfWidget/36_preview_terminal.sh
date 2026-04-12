#!/usr/bin/env bash

# fzfw previewer script: write diagnostic info directly to the terminal.
#
# This previewer produces no stdout — fzfw receives nothing and shows no
# preview pane content. Instead it writes directly to /dev/tty so output
# appears in the terminal that launched fzfw. Useful for debugging or
# logging cursor activity without a pane in the window.
#
# Arguments:
#   $1  item text
#   $2  item index
#   $3  selected (1/0)
#   $4  query
#   $5  fzf HTTP port
#   $6  tmpdir

ITEM="$1"
INDEX="$2"
SELECTED="$3"
QUERY="$4"
PORT="$5"
TMPDIR_PATH="$6"

TIMESTAMP=$(date '+%H:%M:%S')

{
    echo "[$TIMESTAMP] cursor -> index=$INDEX  selected=$SELECTED  query='$QUERY'"
    echo "             item  : $ITEM"

    # Use the fzf HTTP port to fetch live match count directly from fzf
    if [ -n "$PORT" ] ; then
        MC=$(curl -s "http://127.0.0.1:$PORT/?limit=1&offset=0" 2>/dev/null \
            | grep -o '"matchCount":[0-9]*' \
            | grep -o '[0-9]*$')
        [ -n "$MC" ] && echo "             matches in fzf : $MC"
    fi

    [ -n "$TMPDIR_PATH" ] && echo "             tmpdir : $TMPDIR_PATH"

} > /dev/tty

# Exit 0 with no stdout — fzfw shows no content in any preview pane
exit 0
