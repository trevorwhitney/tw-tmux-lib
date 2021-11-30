#!/usr/bin/env bash

# set -ex

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Loading tw-tmux-lib"
tmux source -q "${current_dir}/plugin.tmux.conf"
tmux source -q "${current_dir}/solarized.tmux.conf"

# tmux bind + run "cut -c3- ${current_dir}/lib.sh | sh -s _maximize_pane \"#{session_name}\" #D"
# tmux bind m run "cut -c3- ${current_dir}/lib.sh | sh -s _toggle_mouse"
