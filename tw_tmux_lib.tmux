#!/usr/bin/env bash

# set -ex

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Loading tw-tmux-lib"
tmux source -q "${current_dir}/tmux.conf"
tmux source -q "${current_dir}/solarized.tmux.conf"
