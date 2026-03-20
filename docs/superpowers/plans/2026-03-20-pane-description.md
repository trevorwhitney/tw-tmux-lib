# Pane Description (@desc) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display LLM-generated short descriptions on tmux panes created by workmux, using the `@desc` user option.

**Architecture:** Two independent repos. tw-tmux-lib adds status bar display and a manual keybinding. tw-vim-lib adds async LLM-based description generation inside the existing `WorkmuxPrompt` function. tw-tmux-lib ships first.

**Tech Stack:** Bash/tmux config (tw-tmux-lib), Lua/Neovim API (tw-vim-lib), opencode CLI

**Spec:** `docs/2026-03-20-pane-description-design.md` (this repo)

---

## Part 1: tw-tmux-lib (this repo)

### Task 1: Add @desc conditional display to status-left

**Files:**

- Modify: `tmux.conf:13` (status-left-length)
- Modify: `tmux.conf:22-24` (status-left comment and value)

- [ ] **Step 1: Increase status-left-length from 100 to 150**

In `tmux.conf`, change line 13:

```tmux
# Before
set -g status-left-length 100

# After
set -g status-left-length 150
```

- [ ] **Step 2: Add @desc conditional to status-left**

In `tmux.conf`, change lines 22-24:

```tmux
# Before
# Status left: time | hostname | git branch | session
set -g status-left-style "default"
set -g status-left "%H:%M:%S | 󰟀 #(hostname) | #{git_status}| 󱎂 #S "

# After
# Status left: time | hostname | git branch | desc (if set) | session
set -g status-left-style "default"
set -g status-left "%H:%M:%S | 󰟀 #(hostname) | #{git_status}| #{?@desc,#{@desc} | ,}󱎂 #S "
```

The `#{?@desc,#{@desc} | ,}` conditional renders the description with a
trailing ` | ` separator when set, or nothing when unset/empty.

- [ ] **Step 3: Verify manually**

Reload tmux config and test:

```bash
# Reload
tmux source-file ~/.config/tmux/tmux.conf

# Set a test description on current pane
tmux set -p @desc "test description"
# Verify it appears in status bar between git branch and session name

# Clear it
tmux set -pu @desc
# Verify it disappears and no stray separator remains
```

- [ ] **Step 4: Commit**

```bash
git add tmux.conf
git commit -m "feat: display @desc pane user option in status-left"
```

### Task 2: Add prefix C-t keybinding for manual description entry

**Files:**

- Modify: `tmux.conf` (add after line 89, near other keybindings)

- [ ] **Step 1: Add the keybinding**

In `tmux.conf`, add after the `bind C-d detach` line (line 89):

```tmux
# set pane description (shown in status bar when set)
bind C-t command-prompt -p "pane description:" "set -p @desc '%%'"
```

- [ ] **Step 2: Verify manually**

```bash
# Reload config
tmux source-file ~/.config/tmux/tmux.conf

# Press prefix C-t, type "my test desc", press enter
# Verify @desc appears in status bar

# Press prefix C-t, press enter with empty input
# Verify description disappears from status bar
```

- [ ] **Step 3: Commit**

```bash
git add tmux.conf
git commit -m "feat: add prefix C-t keybinding to set pane description"
```

---

## Part 2: tw-vim-lib (separate repo: ~/workspace/tw-vim-lib/tw-vim-lib)

### Task 3: Add async description generation to WorkmuxPrompt

**Files:**

- Modify: `lua/tw/agent/init.lua:816-852` (WorkmuxPrompt function)

- [ ] **Step 1: Add the generate_pane_description helper function**

In `lua/tw/agent/init.lua`, add a new local function *before* `WorkmuxPrompt`
(before line 816). This function encapsulates the async LLM call and tmux
set logic:

```lua
--- Generate a short pane description from prompt text via LLM and set @desc.
--- Fire-and-forget: errors are logged but never disrupt the user.
local function generate_pane_description(prompt_text)
	-- Guard: need opencode binary and tmux environment
	if vim.fn.executable("opencode") ~= 1 then
		log.debug("generate_pane_description: opencode not found, skipping")
		return
	end
	if not os.getenv("TMUX") then
		log.debug("generate_pane_description: not in tmux, skipping")
		return
	end

	local instructions = "Summarize this task in 3-5 words. "
		.. "Output ONLY the summary, nothing else. "
		.. "No quotes, no punctuation, no explanation."
	local capped_prompt = prompt_text:sub(1, 2000)
	local message = instructions .. " The task: " .. capped_prompt

	vim.system(
		{ "opencode", "run", "--format", "json", "--model", "anthropic/claude-haiku-4-5", message },
		{ timeout = 15000 },
		function(result)
			-- Schedule back to main loop for safe vim API access
			vim.schedule(function()
				if result.code ~= 0 then
					log.warn("generate_pane_description: opencode exited with code " .. tostring(result.code))
					return
				end

				local stdout = result.stdout or ""
				if stdout == "" then
					log.warn("generate_pane_description: opencode returned empty output")
					return
				end

				-- Parse NDJSON: collect .part.text from all type=="text" objects
				local parts = {}
				for line in stdout:gmatch("[^\n]+") do
					local ok, decoded = pcall(vim.json.decode, line)
					if ok and type(decoded) == "table" and decoded.type == "text" then
						local text = decoded.part and decoded.part.text
						if text then
							table.insert(parts, text)
						end
					end
				end

				local raw = table.concat(parts, " ")

				-- Sanitization pipeline (order matters):
				-- 1. Strip leading/trailing whitespace
				raw = vim.trim(raw)
				-- 2. Take substring up to the first newline
				raw = raw:match("^([^\n]*)") or raw
				-- 3. Strip surrounding single and double quotes
				raw = raw:gsub("^[\"']+", ""):gsub("[\"']+$", "")
				-- 4. Strip non-printable/control characters (keep printable ASCII + UTF-8)
				raw = raw:gsub("[%c]", "")
				-- 5. Truncate to max 50 characters
				raw = raw:sub(1, 50)
				-- Final trim in case truncation left trailing space
				raw = vim.trim(raw)

				if raw == "" then
					log.warn("generate_pane_description: sanitized description is empty")
					return
				end

				log.info("generate_pane_description: setting @desc = " .. raw)
				vim.system({ "tmux", "set", "-p", "@desc", raw }, {}, function(tmux_result)
					vim.schedule(function()
						if tmux_result.code ~= 0 then
							log.warn("generate_pane_description: tmux set failed with code " .. tostring(tmux_result.code))
						end
					end)
				end)
			end)
		end
	)
end
```

- [ ] **Step 2: Call generate_pane_description from WorkmuxPrompt**

In the `WorkmuxPrompt` function, add the call after `prompt_text` is
constructed (after line 838) and before the prompt files are deleted
(before line 840):

```lua
	local prompt_text = table.concat(lines, "\n")

	-- Generate a short pane description asynchronously (fire-and-forget)
	generate_pane_description(prompt_text)

	-- Clean up all prompt files so they aren't re-sent on restart
```

- [ ] **Step 3: Verify manually**

1. Start a tmux session
2. Use `prefix C-a` to create a new workmux worktree with a prompt
3. Switch to the new window
4. Wait 2-5 seconds for the LLM to respond
5. Check the status bar — the description should appear between git branch
   and session name
6. Verify with: `tmux show-options -p @desc`

Test error paths:
- Create a worktree without a prompt file — no `@desc` should be set
- Temporarily rename `opencode` binary — should log debug and skip silently

- [ ] **Step 4: Commit**

```bash
git add lua/tw/agent/init.lua
git commit -m "feat: generate pane description from workmux prompt via LLM"
```
