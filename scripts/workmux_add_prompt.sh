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

# --- fzf directory picker ---
WORKSPACE="$HOME/workspace"

if ! command -v fzf >/dev/null 2>&1; then
	log "fzf not found"
	echo "fzf is required but not installed."
	echo "Press enter to close."
	read
	rm -f "$TMPFILE"
	exit 1
fi

SELECTION=$(for d in "$WORKSPACE"/*/; do basename "$d"; done | fzf --reverse --prompt="repo> ")
FZF_EXIT=$?
log "fzf exited with code $FZF_EXIT, selection: '$SELECTION'"

# Exit 130 = user cancelled (Ctrl-C/Esc), exit 0 with empty = no selection
# Any other non-zero = fzf error
if [ -z "$SELECTION" ] && [ $FZF_EXIT -eq 0 ]; then
	log "Empty selection, exiting"
	rm -f "$TMPFILE"
	exit 0
fi

if [ $FZF_EXIT -eq 130 ]; then
	log "fzf cancelled by user, exiting"
	rm -f "$TMPFILE"
	exit 0
fi

if [ $FZF_EXIT -ne 0 ]; then
	log "fzf failed with exit code $FZF_EXIT"
	echo "fzf failed (exit $FZF_EXIT)."
	echo "Press enter to close."
	read
	rm -f "$TMPFILE"
	exit 1
fi

WORKTREE_ROOT="${WORKSPACE}/${SELECTION}/${SELECTION}"
if [ ! -d "$WORKTREE_ROOT" ]; then
	log "Worktree root not found: $WORKTREE_ROOT"
	echo "No worktree root found at ${WORKTREE_ROOT}"
	echo "Expected <repo>/<repo> convention. Set up worktrees first."
	echo ""
	echo "Press enter to close."
	read
	rm -f "$TMPFILE"
	exit 1
fi

cd "$WORKTREE_ROOT" || {
	log "Failed to cd into $WORKTREE_ROOT"
	echo "Failed to cd into $WORKTREE_ROOT"
	echo "Press enter to close."
	read
	rm -f "$TMPFILE"
	exit 1
}
log "Changed directory to $WORKTREE_ROOT"

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
