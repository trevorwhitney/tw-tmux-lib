#!/usr/bin/env bash
current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Loading tw-tmux-lib"
tmux source -q "${current_dir}/plugin.tmux.conf"
