# Design: fzf Directory Picker for workmux_add_prompt.sh

## Problem

`workmux_add_prompt.sh` (bound to `prefix + C-a`) runs `workmux add` in the
current pane's working directory. To create a worktree in a different repo, you
must first navigate to that repo's root — which defeats the convenience of the
popup and makes the CLI more practical.

## Solution

Add an fzf directory picker step before the vim prompt editor. The picker lists
workspace repos and resolves them to the correct worktree root using an
established naming convention.

## Worktree Convention

Repos with worktrees follow `~/workspace/<repo>/<repo>` where the inner
directory matching the repo name is the default branch (main/master) worktree
root. Repos without worktrees sit directly at `~/workspace/<repo>` with no
inner matching directory.

## Flow

1. List directories under `~/workspace` (depth 1) and pipe to `fzf --reverse`.
2. User picks a repo name (e.g. `loki`).
3. Script resolves to `~/workspace/loki/loki`.
4. If the resolved path doesn't exist or isn't a directory, show an error and
   exit:
   ```
   No worktree root found at ~/workspace/loki/loki
   Expected <repo>/<repo> convention. Set up worktrees first.
   Press enter to close.
   ```
5. If user cancels fzf (Esc/Ctrl-C), exit cleanly — no vim, no error.
6. `cd` into the resolved path.
7. Open vim (minimal vimrc) for the prompt — unchanged from today.
8. Run `workmux add -A -P <tmpfile>` — unchanged from today.

## Keybinding

No changes. `prefix + C-a` stays bound to
`display-popup -d "#{pane_current_path}" -h 30 -w 100 -E <script>`. The `-d`
flag becomes a no-op since the script always `cd`s to the resolved path, but
it's harmless to leave in place.

## Decisions

- **Always show fzf** — no option to skip the picker or use the current
  directory. Consistent single flow.
- **`cd` in the script** — the popup's `-d` is set at launch and can't be
  changed after fzf completes. `cd` is the simplest override.
- **No legacy support** — the `~/workspace/<repo>/main` convention is being
  migrated away from and won't be handled.
