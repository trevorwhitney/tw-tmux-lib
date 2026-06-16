#!/bin/bash
# Background helper for workmux_add_prompt.sh
# Called via: tmux run-shell -b '...workmux_add_bg.sh <tmpfile> <logfile> <worktree_root>'
# Runs `workmux add -A` detached from the popup process so the LLM-based name
# generation happens after the popup closes. Reports results via
# tmux display-message.

set -euo pipefail

TMPFILE="$1"
LOGFILE="$2"
WORKTREE_ROOT="$3"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOGFILE"
}

cd "$WORKTREE_ROOT" || {
	log "bg: failed to cd into $WORKTREE_ROOT"
	tmux display-message -d 5000 "workmux failed in $WORKTREE_ROOT — see $LOGFILE"
	rm -f "$TMPFILE"
	exit 1
}

log "bg: starting workmux add -A -b -P $TMPFILE in $WORKTREE_ROOT"
if workmux add -A -b -P "$TMPFILE" >>"$LOGFILE" 2>&1; then
	log "workmux exited successfully"
	tmux display-message "Worktree created in background (auto-named)"
else
	EXIT_CODE=$?
	log "workmux exited with code $EXIT_CODE"
	tmux display-message -d 5000 "workmux failed in $WORKTREE_ROOT — see $LOGFILE"
fi

rm -f "$TMPFILE"
