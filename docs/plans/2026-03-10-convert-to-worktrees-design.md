# Design: convert_to_worktrees.sh

## Problem

Plain git repos in `~/workspace` don't follow the `<repo>/<repo>` worktree
convention required by the fzf directory picker in `workmux_add_prompt.sh`.
Converting them manually is tedious. A one-time script automates the safe cases
and flags the rest for manual attention.

## Solution

A standalone script at `scripts/convert_to_worktrees.sh` that scans
`~/workspace`, classifies repos as safe or unsafe to convert, reports findings,
asks for confirmation, then converts the safe ones.

## Flow

1. **Scan** `~/workspace` for directories needing conversion:
   - Skip directories already in `<repo>/<repo>` convention
   - Skip non-git directories
   - Identify plain git repos at `~/workspace/<name>`

2. **Classify** each candidate:
   - **Unsafe** if: uncommitted changes (staged or unstaged), untracked files,
     any local branch with no upstream, or any branch ahead of its upstream
   - **Safe** otherwise

3. **Report** findings:
   ```
   Ready to convert (clean):
     ~/workspace/foo
     ~/workspace/bar

   Needs manual attention:
     ~/workspace/baz — dirty working tree
     ~/workspace/qux — branch 'feature-x' has no upstream
     ~/workspace/quux — branch 'main' is 2 commits ahead of origin/main
   ```

4. **Confirm**: "Convert N clean repos? [y/N]"

5. **Convert** each safe repo:
   - `git remote get-url origin` to save the URL
   - `rm -rf ~/workspace/<name>`
   - `mkdir ~/workspace/<name>`
   - `cd ~/workspace/<name> && git clone <URL>`
   - This produces `~/workspace/<name>/<name>`

6. **Summary** of what was converted and what was skipped

## Error Handling

If a conversion fails mid-way (e.g., clone fails after deletion), report the
failure loudly and continue with remaining repos. The user needs to see and fix
partial failures manually.

## Decisions

- **Report-then-confirm** — no automatic conversion without user approval
- **Thorough safety checks** — dirty tree, untracked files, local-only branches,
  branches ahead of upstream. All must pass for a repo to be considered safe.
- **Lives in `scripts/`** in this repo alongside the other utilities
- **One-time use** — no need for idempotency or re-run logic
