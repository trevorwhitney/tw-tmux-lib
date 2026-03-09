# fzf Directory Picker for workmux_add_prompt.sh — Implementation Plan

**Goal:** Add an fzf directory picker before the vim prompt in `workmux_add_prompt.sh` so users can select a workspace repo without navigating to it first.

**Approach:** Insert an fzf step before vim that lists `~/workspace` subdirectories, resolves to `<repo>/<repo>` worktree convention, validates, `cd`s, then continues existing flow.

**Tech Stack:** Bash, fzf, tmux display-popup (existing)

**Assumptions:** Directory names in `~/workspace` contain no spaces or special characters (standard for git repos). fzf is installed (already required by tmux.conf session/window switchers).

---

### Task 1: Add fzf directory picker and path resolution

**Files:**
- Modify: `scripts/workmux_add_prompt.sh` (insert after line 18, before the vim call at line 20)

**Reuse:**
- fzf popup style from `tmux.conf:81` (`fzf --reverse`)
- Logging pattern (`log()` already in the script)
- Error-handling pattern matches existing blocks in the script (lines 24-30). Duplicated intentionally — not worth abstracting for 3 call sites.

**Step 1: Insert the fzf picker, resolution, and cd logic**

Insert after `log "--- Script started ---"` (line 18) and before the `vim` call (line 20):

```bash
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

SELECTION=$(ls -d "$WORKSPACE"/*/ 2>/dev/null | xargs -n1 basename | fzf --reverse --prompt="repo> ")
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
```

Key changes from initial draft:
- `ls -d "$WORKSPACE"/*/` + `xargs -n1 basename` — lists only directories, strips paths to bare names
- `command -v fzf` guard before invocation
- fzf exit 130 (user cancel) → exit 0; other non-zero → exit 1 with error message

### Task 2: Manual smoke test

No automated test infra in this project. Test manually:

**Test 1: Happy path**
- Press `prefix + C-a`
- fzf picker appears listing only directories from `~/workspace`
- Select a repo with `<repo>/<repo>` convention
- Vim opens, write a prompt, `:wq`
- `workmux add` runs successfully
- **Verify:** check `~/.cache/tw-tmux-lib/workmux_add_prompt.log` — confirm "Changed directory to" shows the selected repo path, and the workmux command ran from that directory

**Test 2: Cancel fzf**
- Press `prefix + C-a`, press `Esc` in fzf
- Popup closes cleanly, no vim, no error

**Test 3: Non-worktree repo + Empty prompt**
- Select a repo without `<repo>/<repo>` structure — error message appears, press Enter to close
- Select a valid repo, vim opens, `:q!` — popup closes, no workmux invocation

### Task 3: Commit

After smoke tests pass:

```bash
git add scripts/workmux_add_prompt.sh
git commit -m "feat: add fzf directory picker to workmux add prompt"
```
