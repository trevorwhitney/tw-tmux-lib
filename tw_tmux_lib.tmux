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

background=${BACKGROUND:-light}
theme=${TMUX_THEME:-everforest}
if [[ "${theme}" == "solarized" ]]; then
	if [[ "${background}" == "dark" ]]; then
		tmux source -q "${current_dir}/solarized-dark.tmux.conf"
	else
		tmux source -q "${current_dir}/solarized-light.tmux.conf"
	fi
elif [[ "${theme}" == "flexoki" ]]; then
	if [[ "${background}" == "dark" ]]; then
		tmux source -q "${current_dir}/flexoki-dark.tmux.conf"
	else
		tmux source -q "${current_dir}/flexoki-light.tmux.conf"
	fi
elif [[ "${theme}" == "everforest" ]]; then
	if [[ "${background}" == "dark" ]]; then
		tmux source -q "${current_dir}/everforest-dark.tmux.conf"
	else
		tmux source -q "${current_dir}/everforest-light.tmux.conf"
	fi
fi

if [[ $(uname) == "Darwin" ]]; then
	tmux source -q "${current_dir}/clipboard-macos.tmux.conf"
else
	tmux source -q "${current_dir}/clipboard-linux.tmux.conf"
fi

tmux source -q "${current_dir}/tmux.conf"

tmux bind c run "${current_dir}/scripts/new_window_prompt.sh"
tmux bind t run "${current_dir}/scripts/new_tmp.sh"

tmux set-option -gq status-left "$(do_interpolation "$(tmux show-options -gv status-left)")"
tmux set-option -gq status-right "$(do_interpolation "$(tmux show-options -gv status-right)")"
