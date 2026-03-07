#!/usr/bin/env bash

# set -ex

current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

interpolation=(
	"\#{updates_available}"
	"\#{disk_usage}"
)
commands=(
	"#($current_dir/scripts/updates_available.sh)"
	"#($current_dir/scripts/disk_usage.sh)"
)

do_interpolation() {
	local all_interpolated="$1"
	for ((i = 0; i < ${#commands[@]}; i++)); do
		all_interpolated=${all_interpolated//${interpolation[$i]}/${commands[$i]}}
	done
	echo "$all_interpolated"
}

if [[ $(uname) == "Darwin" ]]; then
	tmux source -q "${current_dir}/clipboard-macos.tmux.conf"
else
	tmux source -q "${current_dir}/clipboard-linux.tmux.conf"
fi

tmux source -q "${current_dir}/tmux.conf"

tmux bind c run "${current_dir}/scripts/new_window_prompt.sh"
tmux bind t run "${current_dir}/scripts/new_tmp.sh"
tmux bind C-a display-popup -d "#{pane_current_path}" -h 30 -w 100 -E "${current_dir}/scripts/workmux_add_prompt.sh"

tmux set-option -gq status-left "$(do_interpolation "$(tmux show-options -gv status-left)")"
tmux set-option -gq status-right "$(do_interpolation "$(tmux show-options -gv status-right)")"
