# Vim-Embedded Agent in Workmux Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When workmux creates a pane, launch nvim instead of a standalone opencode agent, and have vim auto-detect the workmux prompt file and send it to an embedded opencode agent.

**Architecture:** The script calls `workmux add` without `-P` (creating the worktree), then writes the prompt to `.workmux/PROMPT-<branch>.md` inside the newly created worktree (same location workmux uses). Vim detects the prompt file on `VimEnter`, opens opencode via the existing agent module, sends the prompt content, and deletes the file so it isn't re-sent on restart. The workmux config change (pane command `<agent>` to `nvim`) happens last to avoid a broken intermediate state.

**Tech Stack:** Bash (script), Lua/Neovim (tw-vim-lib), YAML (workmux config)

**Repos involved:**
- `tw-tmux-lib` (this repo): `scripts/workmux_add_prompt.sh`
- `tw-vim-lib`: `lua/tw/agent/init.lua`, `lua/tw/agent/commands.lua`
- `dotfiles`: `workmux/config.yaml`

---

### Task 1: Modify `workmux_add_prompt.sh` to write prompt file directly

**Files:**

- Modify: `~/workspace/tw-tmux-lib/slim-fern/scripts/workmux_add_prompt.sh`
- Modify: `~/workspace/tw-tmux-lib/slim-fern/docs/vim-agent-in-workmux.md`

The script currently passes `-P $TMPFILE` to `workmux add`, which makes workmux
parse the frontmatter and write the resolved prompt. Since we're skipping `-P`
(to avoid the agent pane validation error), the script needs to write the prompt
file itself after `workmux add` creates the worktree.

- [ ] **Step 1: Remove frontmatter from prompt template**

Replace the template block (lines 99-109) with:

```bash
# TODO: Restore frontmatter template when workmux#82 is resolved
# and we can pass -P to workmux again for prompt parsing.
# See: https://github.com/raine/workmux/issues/82
: > "$TMPFILE"
```

- [ ] **Step 2: Update script to write prompt after workmux add**

Use `workmux path $NAME` to find the worktree path after creation.

Replace the `workmux add` invocation (lines 127-144) with:

```bash
CURRENT_HASH=$(md5 -q "$TMPFILE" 2>/dev/null || md5sum "$TMPFILE" | cut -d' ' -f1)
if [ "$CURRENT_HASH" != "$TEMPLATE_HASH" ]; then
	NAME=$(generate_name)
	log "Prompt content: $(cat "$TMPFILE")"
	log "Generated name: $NAME"
	log "Running: workmux add $NAME -b (without prompt)"

	workmux add "$NAME" -b 2>&1 | tee -a "$LOGFILE"
	EXIT_CODE=${PIPESTATUS[0]}
	log "workmux exited with code $EXIT_CODE"

	if [ $EXIT_CODE -eq 0 ]; then
		# Write prompt file to the worktree
		WORKTREE_PATH=$(workmux path "$NAME" 2>/dev/null)
		if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
			PROMPT_DIR="${WORKTREE_PATH}/.workmux"
			mkdir -p "$PROMPT_DIR"
			PROMPT_FILE="${PROMPT_DIR}/PROMPT-${NAME}.md"
			cp "$TMPFILE" "$PROMPT_FILE"
			log "Wrote prompt to $PROMPT_FILE"
		else
			log "WARNING: Could not determine worktree path for $NAME"
		fi
		tmux display-message "Worktree '$NAME' created in background"
	else
		tmux display-message -d 5000 "workmux failed for '$NAME' — see $LOGFILE"
	fi
else
	log "Empty prompt, skipping workmux add"
fi
```

- [ ] **Step 3: Update design doc status**

In `docs/vim-agent-in-workmux.md`, change status from "Blocked" to
"Implemented (workaround)" and note that this is the interim solution
pending workmux#82.

- [ ] **Step 4: Commit**

```bash
git add scripts/workmux_add_prompt.sh docs/vim-agent-in-workmux.md
git commit -m "feat: write prompt file directly instead of passing -P to workmux

Workaround for workmux#82: workmux requires an agent pane to accept
-P flag. Write the prompt to .workmux/PROMPT-<branch>.md ourselves
after workmux creates the worktree. Frontmatter template commented
out until the issue is resolved."
```

---

### Task 2: Add workmux prompt detection to tw-vim-lib

**Files:**

- Modify: `~/workspace/tw-vim-lib/tw-vim-lib/lua/tw/agent/init.lua` (add WorkmuxPrompt function)
- Modify: `~/workspace/tw-vim-lib/tw-vim-lib/lua/tw/agent/commands.lua` (add VimEnter autocmd)

On `VimEnter`, check for `.workmux/PROMPT-*.md` in the cwd. If found, open
opencode with `--prompt "$(cat <file>)"` so the prompt is passed on the command
line at startup -- no timing dependency on the TUI being ready. Delete the
prompt file after opencode launches so it isn't re-used on restart.

- [ ] **Step 1: Add `WorkmuxPrompt` function to init.lua**

Add to `init.lua` before the `M.setup` function. This passes the prompt file
to opencode via `--prompt "$(cat ...)"` -- the same mechanism workmux itself
uses (see `agent.rs` `OpenCodeProfile.prompt_argument`). The shell expansion
handles all escaping, and opencode receives the prompt natively at startup:

```lua
function M.WorkmuxPrompt()
	-- Find .workmux/PROMPT-*.md in cwd
	local cwd = vim.fn.getcwd()
	local workmux_dir = cwd .. "/.workmux"
	local prompt_files = vim.fn.glob(workmux_dir .. "/PROMPT-*.md", false, true)

	if #prompt_files == 0 then
		return
	end

	-- Use the first (should be only) prompt file
	local prompt_file = prompt_files[1]
	log.info("Found workmux prompt: " .. prompt_file)

	-- Pass prompt to opencode via --prompt "$(cat <file>)" (same as workmux)
	local prompt_arg = '--prompt "$(cat ' .. vim.fn.shellescape(prompt_file) .. ')"'
	M.Open("opencode", { prompt_arg }, "vsplit")

	-- Delete the file so it isn't re-sent on restart
	vim.fn.delete(prompt_file)
end
```

- [ ] **Step 2: Add VimEnter autocmd to commands.lua**

In `setup_autocmds`, add after the existing `VimLeavePre` autocmd:

```lua
-- Detect workmux prompt file on startup
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		-- Slight delay to let vim fully initialize
		vim.defer_fn(function()
			claude_module.WorkmuxPrompt()
		end, 100)
	end,
	group = group,
	desc = "Detect and send workmux prompt to agent on startup",
})
```

- [ ] **Step 3: Test prompt detection**

Nvim is configured via a nix flake in tw-vim-lib, so changes must be picked up
by the flake before testing:

1. `cd ~/workspace/tw-vim-lib/tw-vim-lib` (or the working branch)
2. Run `direnv reload` to rebuild nvim with the updated plugin
3. Create a test prompt file: `mkdir -p .workmux && echo "Hello, tell me a joke" > .workmux/PROMPT-test.md`
4. Open nvim in that directory
5. Verify: opencode agent opens automatically with the prompt pre-filled
6. Verify: `.workmux/PROMPT-test.md` has been deleted
7. Reopen nvim -- verify no agent opens (file was consumed)

- [ ] **Step 4: Commit**

```bash
git add lua/tw/agent/init.lua lua/tw/agent/commands.lua
git commit -m "feat: auto-detect workmux prompt and launch opencode with it

On VimEnter, checks for .workmux/PROMPT-*.md in cwd. If found, launches
opencode with --prompt flag (same mechanism workmux uses) and deletes
the file to prevent re-launch on restart."
```

---

### Task 3: Change workmux config pane command from `<agent>` to `nvim`

**Files:**

- Modify: `~/workspace/dotfiles/dotfiles/workmux/config.yaml`

This task is last because Tasks 1 and 2 must be in place before we switch from
the agent pane to nvim. Otherwise new workmux panes would open nvim with no
prompt injection mechanism.

- [ ] **Step 1: Update pane command**

Change the pane configuration from:
```yaml
panes:
  - command: <agent>
    focus: true
```
to:
```yaml
panes:
  - command: nvim
    focus: true
```

Keep `agent: opencode` in the config -- it's still used for other workmux
features (auto-naming, etc.) and will be needed when workmux#82 lands.

- [ ] **Step 2: Commit**

```bash
git add workmux/config.yaml
git commit -m "feat: change workmux pane command from agent to nvim

Completes the vim-embedded agent workflow: new workmux panes open nvim
instead of a standalone opencode process. Vim auto-detects the prompt
file and launches an embedded agent."
```

---

### Task 4: End-to-end smoke test (manual)

**This task must be done by the user manually.** Prompt the user when it's time.

- [ ] **Step 1: Full flow verification**

1. Trigger the tmux binding (prefix + C-a)
2. Pick a repo via fzf
3. Write a prompt in the editor
4. Verify: worktree created, nvim opens in the pane
5. Verify: `.workmux/PROMPT-<name>.md` was created and consumed
6. Verify: opencode agent opened inside nvim with the prompt
7. Open nvim in a directory without `.workmux/PROMPT-*.md` -- verify no agent opens

---

## Future: When workmux#82 lands

Once workmux supports writing the prompt file without an agent pane:

1. Revert `workmux_add_prompt.sh` changes -- go back to passing `-P $TMPFILE`
   to workmux so it handles frontmatter parsing and template resolution
2. Restore the frontmatter template in `workmux_add_prompt.sh` (marked with
   `TODO: Restore frontmatter template when workmux#82 is resolved`)
3. The vim-side changes (prompt detection) stay the same
4. Multi-worktree `foreach:` prompts will work again
