#!/bin/bash

# Git branch + dirty status for tmux status bar
# Uses ANSI colour2 (green) for clean, colour3 (yellow) for dirty
# These map to terminal theme colors automatically (light/dark)

pane_path="$1"
if [ -z "$pane_path" ]; then
  pane_path="$(tmux display-message -p '#{pane_current_path}')"
fi

# Bail if the directory doesn't exist
[ -d "$pane_path" ] || exit 0

cd "$pane_path" || exit 0

# Check if we're in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# Get branch name (or short SHA for detached HEAD)
branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || \
  branch="➦ $(git rev-parse --short HEAD 2>/dev/null)"

[ -z "$branch" ] && exit 0

# Check dirty status
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  # Dirty: yellow (colour3) with  icon
  echo "#[fg=colour3] ${branch} #[default]"
else
  # Clean: green (colour2) with  icon
  echo "#[fg=colour2] ${branch} #[default]"
fi
