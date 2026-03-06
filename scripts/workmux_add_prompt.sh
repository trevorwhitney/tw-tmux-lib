#!/bin/bash

# Opens a minimal vim editor for writing a workmux prompt,
# then creates a new worktree with an LLM-generated branch name.

TMPFILE=$(mktemp /tmp/workmux-prompt.XXXXXX)

vim -u NONE "$TMPFILE"

# Only create the worktree if the user saved content
if [ -s "$TMPFILE" ]; then
	workmux add -A -P "$TMPFILE"
fi

rm -f "$TMPFILE"
