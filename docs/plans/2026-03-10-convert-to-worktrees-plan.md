# convert_to_worktrees.sh Implementation Plan

**Goal:** Create a one-time script that converts plain git repos in `~/workspace` to the `<repo>/<repo>` directory convention used by workmux, with safety checks and user confirmation.

**Approach:** Single bash script with three phases: scan/classify, report/confirm, convert. Safety checks use `git status --porcelain` and `git for-each-ref` + `git rev-list` to detect dirty state and unpushed branches. Conversion uses `mv` to backup before cloning, with automatic rollback on failure.

**Tech Stack:** Bash, git

---

### Task 1: Create the complete script

**Files:**
- Create: `scripts/convert_to_worktrees.sh`

**Reuse:** None — greenfield script.

**Step 1: Create the script**

Create `scripts/convert_to_worktrees.sh` with the complete implementation:

```bash
#!/bin/bash

# One-time script to convert plain git repos in ~/workspace
# to the <repo>/<repo> directory convention used by workmux.
#
# For each plain repo ~/workspace/foo, this script:
#   1. Checks safety (clean tree, no unpushed branches)
#   2. Moves to ~/workspace/foo.bak
#   3. Clones into ~/workspace/foo/foo
#   4. Removes backup on success, restores on failure
#
# Usage: ./scripts/convert_to_worktrees.sh

set -euo pipefail

WORKSPACE="$HOME/workspace"

# Arrays to collect results
SAFE_REPOS=()
UNSAFE_REPOS=()
UNSAFE_REASONS=()
SKIPPED=()

check_repo() {
	local dir="$1"
	local name
	name=$(basename "$dir")
	local reasons=()

	# Check for uncommitted changes (staged, unstaged, untracked)
	if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
		reasons+=("dirty working tree")
	fi

	# Check all local branches for upstream status
	while IFS= read -r branch; do
		[ -z "$branch" ] && continue

		upstream=$(git -C "$dir" config --get "branch.${branch}.remote" 2>/dev/null || true)
		if [ -z "$upstream" ]; then
			reasons+=("branch '$branch' has no upstream")
			continue
		fi

		ahead=$(git -C "$dir" rev-list --count "${branch}@{upstream}..${branch}" 2>/dev/null || echo "0")
		if [ "$ahead" -gt 0 ]; then
			reasons+=("branch '$branch' is $ahead commit(s) ahead of upstream")
		fi
	done < <(git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads/)

	if [ ${#reasons[@]} -gt 0 ]; then
		UNSAFE_REPOS+=("$name")
		UNSAFE_REASONS+=("$(IFS='; '; echo "${reasons[*]}")")
	else
		SAFE_REPOS+=("$name")
	fi
}

# --- Scan ---
echo "Scanning ~/workspace..."
echo ""

for dir in "$WORKSPACE"/*/; do
	[ ! -d "$dir" ] && continue
	name=$(basename "$dir")

	# Already converted: inner dir with same name exists and is a git repo
	if [ -d "${dir}${name}/.git" ]; then
		SKIPPED+=("$name (already converted)")
		continue
	fi

	# Not a git repo
	if [ ! -d "${dir}.git" ]; then
		SKIPPED+=("$name (not a git repo)")
		continue
	fi

	# No origin remote
	if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
		UNSAFE_REPOS+=("$name")
		UNSAFE_REASONS+=("no 'origin' remote configured")
		continue
	fi

	check_repo "$dir"
done

# --- Report ---
if [ ${#SKIPPED[@]} -gt 0 ]; then
	echo "Skipped (${#SKIPPED[@]}):"
	for entry in "${SKIPPED[@]}"; do
		echo "  $entry"
	done
	echo ""
fi

if [ ${#UNSAFE_REPOS[@]} -gt 0 ]; then
	echo "Needs manual attention (${#UNSAFE_REPOS[@]}):"
	for i in "${!UNSAFE_REPOS[@]}"; do
		echo "  ~/workspace/${UNSAFE_REPOS[$i]} — ${UNSAFE_REASONS[$i]}"
	done
	echo ""
fi

if [ ${#SAFE_REPOS[@]} -eq 0 ]; then
	echo "No repos to convert."
	exit 0
fi

echo "Ready to convert (${#SAFE_REPOS[@]}):"
for name in "${SAFE_REPOS[@]}"; do
	echo "  ~/workspace/$name"
done
echo ""

# --- Confirm ---
read -r -p "Convert ${#SAFE_REPOS[@]} clean repo(s)? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
	echo "Aborted."
	exit 0
fi

echo ""

# --- Convert ---
converted=0
failed=0

for name in "${SAFE_REPOS[@]}"; do
	dir="${WORKSPACE}/${name}"
	backup="${dir}.bak"
	echo "Converting $name..."

	url=$(git -C "$dir" remote get-url origin)
	if [ -z "$url" ]; then
		echo "  ERROR: could not get remote URL for $name, skipping"
		((failed++))
		continue
	fi

	# Move to backup instead of deleting
	mv "$dir" "$backup"

	# Create parent dir and clone
	mkdir -p "$dir"
	if git clone "$url" "$dir/$name" >/dev/null 2>&1 && [ -d "$dir/$name/.git" ]; then
		echo "  OK: ~/workspace/$name/$name"
		rm -rf "$backup"
		((converted++))
	else
		echo "  ERROR: clone failed for $name (remote: $url)"
		echo "  Restoring from backup..."
		rm -rf "$dir"
		mv "$backup" "$dir"
		echo "  Restored ~/workspace/$name"
		((failed++))
	fi
done

echo ""
echo "Done. Converted: $converted, Failed: $failed"
if [ $failed -gt 0 ]; then
	echo "Review failures above and retry manually."
	exit 1
fi
```

**Step 2: Make executable and verify syntax**

```bash
chmod +x scripts/convert_to_worktrees.sh
bash -n scripts/convert_to_worktrees.sh
```

### Task 2: Manual test

Run against `~/workspace`:

1. Answer `N` at the prompt to verify the report looks correct and abort works
2. Run again, answer `y` to convert at least one clean repo
3. Verify `~/workspace/<name>/<name>/.git` exists after conversion
4. Verify the converted repo works with `prefix + C-a` fzf picker

### Task 3: Commit

After successful manual test:

```bash
git add scripts/convert_to_worktrees.sh
git commit -m "feat: add one-time workspace-to-worktree conversion script"
```
