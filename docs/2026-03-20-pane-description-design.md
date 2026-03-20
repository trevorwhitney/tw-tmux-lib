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

**tw-vim-lib** (`lua/tw/agent/init.lua` — `WorkmuxPrompt` function):

After reading the prompt file content (which workmux has already stripped of
YAML frontmatter), and before deleting the prompt files, spawn an async call to
generate a short description:

1. Use `vim.system()` (non-blocking) to pipe the prompt text to `opencode run`
   with a system prompt:

   > Summarize this task in 3-5 words. Output ONLY the summary, nothing else.
   > No quotes, no punctuation, no explanation.

2. In the `on_exit` callback:
   - Trim whitespace, take only the first line, truncate to <50 characters
   - If non-empty, run `tmux set -p @desc "<description>"` via `vim.system()`
     (no `-t` flag needed — we are inside the target pane)
   - Log success or failure

3. Error handling: if `opencode run` fails, returns empty, or times out, log
   and exit silently. The status bar simply won't show a description for that
   pane. No user disruption.

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

2. Add a keybinding for manually setting/updating the description:

   ```
   bind C-d command-prompt -p "pane description:" "set -p @desc '%%'"
   ```

   This covers worktrees created before this feature, or overriding a bad
   LLM-generated description.

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
