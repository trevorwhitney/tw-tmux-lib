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

2. Cap `prompt_text` to the first 2000 characters before building the message
   via `prompt_text:sub(1, 2000)`. This is a silent truncation, not an error —
   the full prompt is still passed to the agent, only the description generation
   sees the capped version. This prevents `ARG_MAX` issues on macOS (256KB
   limit) and avoids sending unnecessarily large payloads to Haiku for a 3-5
   word summary.

3. Use `vim.system()` (non-blocking, argv-style) to call `opencode run`:

   ```lua
   local instructions = "Summarize this task in 3-5 words. "
     .. "Output ONLY the summary, nothing else. "
     .. "No quotes, no punctuation, no explanation."
   local capped_prompt = prompt_text:sub(1, 2000)
   local message = instructions .. " The task: " .. capped_prompt

   vim.system(
     { "opencode", "run", "--format", "json", "--model",
       "anthropic/claude-haiku-4-5", message },
     { timeout = 15000 },
     on_exit_callback
   )
   ```

   The `--format json` flag produces newline-delimited JSON (NDJSON). Each
   line is a separate JSON object. The output includes objects with various
   `type` values. Example output:

   ```json
   {"type":"step_start","timestamp":1774023401936,"sessionID":"ses_...","part":{...}}
   {"type":"text","timestamp":1774023402182,"sessionID":"ses_...","part":{"id":"prt_...","sessionID":"ses_...","messageID":"msg_...","type":"text","text":"Refactor database connection pooling async","time":{...}}}
   {"type":"step_finish","timestamp":1774023402235,"sessionID":"ses_...","part":{...}}
   ```

   The description is in `.part.text` of objects where the top-level `type`
   is `"text"`.

4. In the `on_exit` callback, extract and sanitize the description:
   - Parse each line of stdout as JSON
   - Collect `.part.text` from all objects where `type == "text"`,
     concatenated in order (handles multi-part streaming responses)
   - Apply sanitization pipeline in this order:
     1. Strip leading/trailing whitespace
     2. Take substring up to the first newline (`\n`)
     3. Strip surrounding single and double quotes
     4. Strip any remaining non-printable/control characters
     5. Truncate to max 50 characters
   - If non-empty, set the pane user option via argv-style invocation:

     ```lua
     vim.system({ "tmux", "set", "-p", "@desc", description })
     ```

     No `-t` flag needed — we are inside the target pane. Using argv-style
     (not shell string) eliminates shell injection risk from LLM output.
   - Log success or failure

5. Error handling: if `opencode run` exits non-zero, times out (15s), returns
   empty output, or produces unparseable JSON, log at warn level and exit
   silently. If the subsequent `tmux set` call fails, log at warn level.
   In all failure cases the status bar simply won't show a description for
   that pane. No user disruption.

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

   Note: `@desc` is a native tmux user option resolved at render time, unlike
   `#{git_status}` which requires shell interpolation via `tw_tmux_lib.tmux`.
   No changes to `do_interpolation` or `tw_tmux_lib.tmux` are needed — the
   `#{?@desc,...}` syntax passes through the interpolation function unmodified
   because it doesn't match any custom interpolation pattern.

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
   bind C-t command-prompt -p "pane description:" "set -p @desc '%%'"
   ```

   `prefix C-t` is unbound in the current config and serves as a mnemonic
   for "tag" or "title".

   This covers worktrees created before this feature, or overriding a bad
   LLM-generated description. Entering an empty string sets `@desc` to `""`
   (not truly unset), but the `#{?@desc,...}` conditional treats empty as
   falsy, so the description is hidden from the status bar. To truly unset,
   run `tmux set -pu @desc` manually.

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
- No changes to `tw_tmux_lib.tmux` or its `do_interpolation` function
- No frontmatter stripping needed in tw-vim-lib (workmux already strips it
  before writing `PROMPT-*.md`)
- Pane title and window name are untouched
