# Pane Description via @desc User Option

## Problem

When using `workmux_add_prompt.sh` with random branch names (e.g. `swift-pine`,
`bold-river`), tmux windows accumulate with opaque names. There is no way to
tell at a glance what work is happening in each pane. The window name cannot be
changed because workmux uses it for `workmux merge` and `workmux rm`.

## Solution

Attach a short LLM-generated description to each pane via tmux's user option
`@desc`, and display it in the status bar.

## Design

### Two repos, three changes

The tw-tmux-lib changes are fully independent of the tw-vim-lib changes and
can ship first. Each repo gets its own implementation plan and commit(s).

**tw-vim-lib** (`lua/tw/agent/init.lua` — `WorkmuxPrompt` function):

After reading the prompt file content (which workmux has already stripped of
YAML frontmatter), and before deleting the prompt files, spawn an async call to
generate a short description:

1. Guard: check `vim.fn.executable("opencode") == 1` and `os.getenv("TMUX")`
   is non-nil. If either fails, log at debug level and skip description
   generation entirely.

2. Use `vim.system()` (non-blocking, argv-style) to call `opencode run`:

   ```lua
   local system_prompt = "Summarize this task in 3-5 words. "
     .. "Output ONLY the summary, nothing else. "
     .. "No quotes, no punctuation, no explanation."
   local message = system_prompt .. " The task: " .. prompt_text

   vim.system(
     { "opencode", "run", "--format", "json", "--model",
       "anthropic/claude-haiku-4-5", message },
     { timeout = 15000 },
     on_exit_callback
   )
   ```

   The `--format json` flag produces structured output where the text part has
   `type: "text"` and the description is in `.part.text`. This avoids parsing
   ANSI escape sequences from the default formatted output.

3. In the `on_exit` callback, extract the description from JSON output:
   - Parse each line as JSON, find the object with `type == "text"`
   - Read `.part.text` as the raw description
   - Trim whitespace, take only the first line
   - Strip any non-printable/control characters
   - Truncate to max 50 characters
   - If non-empty, set the pane user option via argv-style invocation:

     ```lua
     vim.system({ "tmux", "set", "-p", "@desc", description })
     ```

     No `-t` flag needed — we are inside the target pane. Using argv-style
     (not shell string) eliminates shell injection risk from LLM output.
   - Log success or failure

4. Error handling: if `opencode run` exits non-zero, times out (15s), returns
   empty output, or produces unparseable JSON, log at warn level and exit
   silently. The status bar simply won't show a description for that pane.
   No user disruption.

**tw-tmux-lib** (`tmux.conf`):

1. Modify `status-left` to display `@desc` when set, positioned between the git
   branch and the session name:

   ```
   # Before
   set -g status-left "%H:%M:%S | 󰟀 #(hostname) | #{git_status}| 󱎂 #S "

   # After
   set -g status-left "%H:%M:%S | 󰟀 #(hostname) | #{git_status}| #{?@desc,#{@desc} | ,}󱎂 #S "
   ```

   The `#{?@desc,#{@desc} | ,}` conditional renders the description with a
   trailing separator when set, or nothing when unset.

   Note: `status-left` is global and `@desc` is pane-local. Tmux resolves
   `#{@desc}` in the context of the active pane. This means the description
   shown is always for the currently focused pane/window. This is the intended
   behavior — when switching between windows, the status bar updates to show
   the description for whichever window you're looking at. Since you focus a
   window to work in it, that's when you need the context.

   Increase `status-left-length` from 100 to 150 to accommodate the
   additional description text (up to ~50 chars plus separator).

2. Add a keybinding for manually setting/updating the description:

   ```
   bind M-d command-prompt -p "pane description:" "set -p @desc '%%'"
   ```

   `prefix M-d` (Alt-d) avoids conflict with the existing `prefix C-d`
   (detach) binding at `tmux.conf:89`.

   This covers worktrees created before this feature, or overriding a bad
   LLM-generated description. Entering an empty string effectively hides the
   description from the status bar (the `#{?@desc,...}` conditional treats
   empty as falsy).

## Why this split

- **tw-vim-lib** is where `WorkmuxPrompt` lives. It already reads the prompt
  content, runs after the pane exists (VimEnter + 100ms defer), and handles
  the "no prompt" early exit. Adding async description generation here avoids
  a new script and the complexity of targeting a background pane by window name.

- **tw-tmux-lib** owns the status bar configuration. It only needs to know how
  to display `@desc` if present.

## Async approach

The LLM call is fire-and-forget. `vim.system()` is non-blocking, so
`WorkmuxPrompt` continues immediately to delete prompt files and launch
opencode with the prompt. The `@desc` appears in the status bar whenever the
LLM responds (typically 1-3 seconds). This avoids any delay to the agent
startup.

## Scope

- No changes to `workmux_add_prompt.sh` (the prompt file and random name
  generation remain unchanged)
- No changes to workmux itself
- No frontmatter stripping needed in tw-vim-lib (workmux already strips it
  before writing `PROMPT-*.md`)
- Pane title and window name are untouched
