#!/bin/bash
# Background helper for workmux_add_prompt.sh
# Called via: tmux run-shell -b '...workmux_add_bg.sh <name> <tmpfile> <logfile> <worktree_root>'
# Runs workmux add detached from the popup process, reports results via tmux display-message.

set -euo pipefail

NAME="$1"
TMPFILE="$2"
LOGFILE="$3"
WORKTREE_ROOT="$4"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOGFILE"
}

cd "$WORKTREE_ROOT" || {
	log "bg: failed to cd into $WORKTREE_ROOT"
	tmux display-message -d 5000 "workmux failed for '$NAME' — see $LOGFILE"
	rm -f "$TMPFILE"
	exit 1
}

log "bg: starting workmux add $NAME -b -P $TMPFILE in $WORKTREE_ROOT"
if workmux add "$NAME" -b -P "$TMPFILE" >>"$LOGFILE" 2>&1; then
	log "workmux exited successfully"
	tmux display-message "Worktree '$NAME' created in background"
else
	EXIT_CODE=$?
	log "workmux exited with code $EXIT_CODE"
	tmux display-message -d 5000 "workmux failed for '$NAME' — see $LOGFILE"
fi

rm -f "$TMPFILE"
