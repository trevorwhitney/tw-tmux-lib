#!/bin/bash

# Opens the default worktree for a selected workspace project.
# Uses fzf to pick a project from ~/workspace/*, then creates
# a new tmux window at ~/workspace/<selection>/<selection>.

LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/tw-tmux-lib"
LOGFILE="${LOGDIR}/open_worktree.log"

mkdir -p "$LOGDIR"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOGFILE"
}

log "--- Script started ---"

# --- fzf directory picker ---
WORKSPACE="$HOME/workspace"

if ! command -v fzf >/dev/null 2>&1; then
	log "fzf not found"
	echo "fzf is required but not installed."
	echo "Press enter to close."
	read
	exit 1
fi

SELECTION=$(for d in "$WORKSPACE"/*/; do basename "$d"; done | fzf --reverse --prompt="open worktree> ")
FZF_EXIT=$?
log "fzf exited with code $FZF_EXIT, selection: '$SELECTION'"

if [ -z "$SELECTION" ] && [ $FZF_EXIT -eq 0 ]; then
	log "Empty selection, exiting"
	exit 0
fi

if [ $FZF_EXIT -eq 130 ]; then
	log "fzf cancelled by user, exiting"
	exit 0
fi

if [ $FZF_EXIT -ne 0 ]; then
	log "fzf failed with exit code $FZF_EXIT"
	echo "fzf failed (exit $FZF_EXIT)."
	echo "Press enter to close."
	read
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
	exit 1
fi

log "Opening new tmux window '$SELECTION' at $WORKTREE_ROOT"
tmux new-window -n "$SELECTION" -c "$WORKTREE_ROOT"
log "--- Script finished ---"
