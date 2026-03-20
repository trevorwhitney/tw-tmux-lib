#!/bin/bash

# Opens a minimal vim editor for writing a workmux prompt,
# then creates a new worktree with a random branch name.
# The worktree's tmux window is created in the background (-b flag).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/tw-tmux-lib"
LOGFILE="${LOGDIR}/workmux_add_prompt.log"
VIMRC="${CURRENT_DIR}/../conf/vimrc.minimal"
TMPFILE=$(mktemp /tmp/workmux-prompt.XXXXXX.md)

mkdir -p "$LOGDIR"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOGFILE"
}

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

# Pre-populate with frontmatter template (commented out)
# Uncomment and edit the foreach lines to use workmux's matrix feature
# Docs: https://workmux.raine.dev/reference/commands/add#variable-matrices-in-prompt-files
cat >"$TMPFILE" <<'TEMPLATE'
---
# Frontmatter docs: https://workmux.raine.dev/reference/commands/add#variable-matrices-in-prompt-files
# foreach:
#   agent: [claude, gemini]
---

TEMPLATE

TEMPLATE_HASH=$(md5 -q "$TMPFILE" 2>/dev/null || md5sum "$TMPFILE" | cut -d' ' -f1)

vim -u "$VIMRC" '+$' "$TMPFILE"
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

CURRENT_HASH=$(md5 -q "$TMPFILE" 2>/dev/null || md5sum "$TMPFILE" | cut -d' ' -f1)
if [ "$CURRENT_HASH" != "$TEMPLATE_HASH" ]; then
	NAME=$(generate_name)
	log "Prompt content: $(cat "$TMPFILE")"
	log "Generated name: $NAME"
	log "Handing off to tmux run-shell: workmux add $NAME -b -P $TMPFILE"

	# Hand off to tmux server so the background work survives popup teardown.
	# tmux run-shell -b runs the command as a server-managed job, fully
	# independent of this script's process group and PTY.
	BG_SCRIPT="${CURRENT_DIR}/workmux_add_bg.sh"
	if ! tmux run-shell -b "$(printf '%q ' "$BG_SCRIPT" "$NAME" "$TMPFILE" "$LOGFILE" "$WORKTREE_ROOT")"; then
		log "ERROR: tmux run-shell failed to launch background job"
		tmux display-message -d 5000 "workmux failed to launch for '$NAME' — see $LOGFILE"
		rm -f "$TMPFILE"
	fi

	log "--- Script finished (workmux handed off to background) ---"
else
	log "Empty prompt, skipping workmux add"
	rm -f "$TMPFILE"
	log "--- Script finished ---"
fi
