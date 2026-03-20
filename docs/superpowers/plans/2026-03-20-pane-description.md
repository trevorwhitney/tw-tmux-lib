# Pane Description (@desc) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display LLM-generated short descriptions on tmux panes created by workmux, using the `@desc` user option.

**Architecture:** Two independent repos. tw-tmux-lib adds status bar display and a manual keybinding. tw-vim-lib adds async LLM-based description generation inside the existing `WorkmuxPrompt` function. tw-tmux-lib ships first.

**Tech Stack:** Bash/tmux config (tw-tmux-lib), Lua/Neovim API (tw-vim-lib), opencode CLI

**Spec:** `docs/2026-03-20-pane-description-design.md` (this repo)

---

## Part 1: tw-tmux-lib (this repo)

### Task 1: Add @desc display and manual keybinding to tmux.conf

**Files:**

- Modify: `tmux.conf` — `status-left-length`, `status-left`, and new keybinding

- [ ] **Step 1: Increase status-left-length from 100 to 150**

Find the `set -g status-left-length 100` line and change to:

```tmux
set -g status-left-length 150
```

- [ ] **Step 2: Add @desc conditional to status-left**

Find the `status-left` line (contains `#{git_status}`) and update the comment
and value:

```tmux
# Status left: time | hostname | git branch | desc (if set) | session
set -g status-left-style "default"
set -g status-left "%H:%M:%S | 󰟀 #(hostname) | #{git_status}| #{?@desc,#{@desc} | ,}󱎂 #S "
```

No changes to `tw_tmux_lib.tmux` or `do_interpolation` are needed — `@desc` is
a native tmux user option that passes through the interpolation function
unmodified.

- [ ] **Step 3: Add prefix C-t keybinding**

After the `bind C-d detach` line, add:

```tmux
# set pane description (shown in status bar when set)
bind C-t command-prompt -p "pane description:" "set -p @desc '%%'"
```

Note: `prefix t` (without Ctrl) is already bound in `tw_tmux_lib.tmux` for
`new_tmp.sh`; `prefix C-t` is distinct and unbound.

- [ ] **Step 4: Verify**

Reload config, then: `tmux set -p @desc "test"` — confirm it appears in
status bar. `tmux set -pu @desc` — confirm it disappears cleanly.

- [ ] **Step 5: Commit**

```bash
git add tmux.conf
git commit -m "feat: display @desc pane description in status-left with C-t keybinding"
```

---

## Part 2: tw-vim-lib (separate repo: ~/workspace/tw-vim-lib/tw-vim-lib)

### Task 2: Add async description generation to WorkmuxPrompt

**Files:**

- Modify: `lua/tw/agent/init.lua` — add helper before `WorkmuxPrompt`, call it from within

Refer to `docs/2026-03-20-pane-description-design.md` sections 1-5 for the
full behavioral spec (guards, command invocation, JSON parsing, sanitization
pipeline, error handling).

- [ ] **Step 1: Add generate_pane_description helper function**

Add a new `local function generate_pane_description(prompt_text)` immediately
before the `function M.WorkmuxPrompt()` definition. The function:

1. Guards: return early if `vim.fn.executable("opencode") ~= 1` or
   `os.getenv("TMUX")` is nil. Log at debug level.
2. Caps prompt to 2000 chars: `prompt_text:sub(1, 2000)`
3. Builds message with instructions prefix (see spec for exact wording)
4. Calls `vim.system()` argv-style with `opencode run --format json --model
   anthropic/claude-haiku-4-5` and 15s timeout
5. In the `on_exit` callback (wrapped in `vim.schedule`):
   - Returns early if exit code ~= 0 or stdout is empty (log warn)
   - Parses NDJSON: iterates lines, `pcall(vim.json.decode, line)`, collects
     `.part.text` from all `type == "text"` objects, concatenates in order
   - Sanitizes: `vim.trim` → strip control chars (`gsub("[%c]", "")`) →
     truncate to 50 chars → final `vim.trim`
   - If non-empty, calls `vim.system({ "tmux", "set", "-p", "@desc", desc })`
     (argv-style, no shell). Logs warn on `tmux` failure.

```lua
--- Generate a short pane description from prompt text via LLM and set @desc.
--- Fire-and-forget: errors are logged but never disrupt the user.
local function generate_pane_description(prompt_text)
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
			vim.schedule(function()
				if result.code ~= 0 then
					log.warn("generate_pane_description: opencode exited with code " .. tostring(result.code))
					return
				end

				local stdout = result.stdout or ""
				if stdout == "" then
					log.warn("generate_pane_description: empty output")
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

				local desc = vim.trim(table.concat(parts, " "))
				desc = desc:gsub("[%c]", "")
				desc = desc:sub(1, 50)
				desc = vim.trim(desc)

				if desc == "" then
					log.warn("generate_pane_description: empty after sanitization")
					return
				end

				log.info("generate_pane_description: @desc = " .. desc)
				vim.system({ "tmux", "set", "-p", "@desc", desc }, {}, function(tmux_result)
					vim.schedule(function()
						if tmux_result.code ~= 0 then
							log.warn("generate_pane_description: tmux set failed: " .. tostring(tmux_result.code))
						end
					end)
				end)
			end)
		end
	)
end
```

- [ ] **Step 2: Call from WorkmuxPrompt**

In `WorkmuxPrompt`, find the line `local prompt_text = table.concat(lines, "\n")`.
Add the call immediately after it, before the file deletion loop:

```lua
	local prompt_text = table.concat(lines, "\n")

	-- Generate a short pane description asynchronously (fire-and-forget)
	generate_pane_description(prompt_text)

	-- Clean up all prompt files so they aren't re-sent on restart
```

- [ ] **Step 3: Verify**

Create a workmux worktree with a prompt via `prefix C-a`. After 2-5s, run
`tmux show-options -p @desc` in the new pane to confirm the description was
set. Note: status bar display requires Part 1 (tw-tmux-lib) to be deployed.

- [ ] **Step 4: Commit**

```bash
git add lua/tw/agent/init.lua
git commit -m "feat: generate pane description from workmux prompt via LLM"
```
