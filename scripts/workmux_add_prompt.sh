#!/bin/bash

# Opens a minimal vim editor for writing a workmux prompt,
# then creates a new worktree with an LLM-generated branch name.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/tw-tmux-lib"
LOGFILE="${LOGDIR}/workmux_add_prompt.log"
VIMRC="${CURRENT_DIR}/../conf/vimrc.minimal"
TMPFILE=$(mktemp /tmp/workmux-prompt.XXXXXX)

mkdir -p "$LOGDIR"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOGFILE"
}

log "--- Script started (pwd: $(pwd)) ---"

vim -u "$VIMRC" "$TMPFILE"
VIM_EXIT=$?
log "vim exited with code $VIM_EXIT"

if [ $VIM_EXIT -ne 0 ]; then
	log "vim exited abnormally"
	echo "vim exited with code $VIM_EXIT"
	echo "Press enter to close."
	read
	rm -f "$TMPFILE"
	exit 1
fi

if [ -s "$TMPFILE" ]; then
	log "Prompt content: $(cat "$TMPFILE")"
	log "Running: workmux add -A -P $TMPFILE"

	workmux add -A -P "$TMPFILE" 2>&1 | tee -a "$LOGFILE"
	EXIT_CODE=${PIPESTATUS[0]}
	log "workmux exited with code $EXIT_CODE"

	if [ $EXIT_CODE -ne 0 ]; then
		echo ""
		echo "workmux failed (exit $EXIT_CODE). Press enter to close."
		read
	fi
else
	log "Empty prompt, skipping workmux add"
fi

rm -f "$TMPFILE"
log "--- Script finished ---"
