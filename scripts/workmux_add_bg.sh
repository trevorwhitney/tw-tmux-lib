#!/bin/bash
# Background helper for workmux_add_prompt.sh
# Called via: tmux run-shell -b '...workmux_add_bg.sh <tmpfile> <logfile> <worktree_root>'
# Runs `workmux add` detached from the popup process so LLM-based name
# generation happens after the popup closes. Reports results via
# tmux display-message.
#
# Naming is defense-in-depth: try workmux's LLM auto-namer (-A) first, and if it
# fails for any reason (broken naming command, network, CLI flag drift), fall
# back to a locally generated adjective-noun name so worktree creation never
# breaks just because naming did.

set -euo pipefail

TMPFILE="$1"
LOGFILE="$2"
WORKTREE_ROOT="$3"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOGFILE"
}

# Local fallback name generator (adjective-noun), used only when -A fails.
generate_name() {
	local adjectives=(
		swift calm bold bright cool dark fast flat fresh
		glad gold keen kind light live long mild neat quick
		rare rich sharp slim smart soft solid strong warm wise
	)
	local nouns=(
		arch bay bird bloom brook cape cave cliff cloud cove
		creek dawn deer dock elm fern finch flame frost glen
		grove hawk hill jade lake lark leaf mesa moon oak
		palm peak pine pond reef ridge sage shore stone trail
	)
	local adj="${adjectives[$((RANDOM % ${#adjectives[@]}))]}"
	local noun="${nouns[$((RANDOM % ${#nouns[@]}))]}"
	echo "${adj}-${noun}"
}

cd "$WORKTREE_ROOT" || {
	log "bg: failed to cd into $WORKTREE_ROOT"
	tmux display-message -d 5000 "workmux failed in $WORKTREE_ROOT — see $LOGFILE"
	rm -f "$TMPFILE"
	exit 1
}

log "bg: starting workmux add -A -b -P $TMPFILE in $WORKTREE_ROOT"
if workmux add -A -b -P "$TMPFILE" >>"$LOGFILE" 2>&1; then
	log "workmux exited successfully (auto-named)"
	tmux display-message "Worktree created in background (auto-named)"
	rm -f "$TMPFILE"
	exit 0
fi

AUTO_EXIT=$?
log "workmux -A failed with code $AUTO_EXIT; falling back to generated name"

NAME="$(generate_name)"
log "bg: retrying with fallback name '$NAME': workmux add $NAME -b -P $TMPFILE"
if workmux add "$NAME" -b -P "$TMPFILE" >>"$LOGFILE" 2>&1; then
	log "workmux exited successfully (fallback name '$NAME')"
	tmux display-message -d 5000 "Auto-name failed; created worktree '$NAME' — see $LOGFILE"
else
	FALLBACK_EXIT=$?
	log "workmux fallback also failed with code $FALLBACK_EXIT"
	tmux display-message -d 5000 "workmux failed in $WORKTREE_ROOT — see $LOGFILE"
fi

rm -f "$TMPFILE"
