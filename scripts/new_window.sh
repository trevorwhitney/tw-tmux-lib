#!/bin/bash

# global variable
WINDOW_NAME="$1"

tmux_socket() {
	echo "$TMUX" | cut -d',' -f1
}

window_name_not_provided() {
	[ -z "$WINDOW_NAME" ]
}

create_new_tmux_window() {
	if window_name_not_provided; then
		TMUX="" tmux -S "$(tmux_socket)" new-window
	else
		TMUX="" tmux -S "$(tmux_socket)" new-window -n "$WINDOW_NAME"
	fi
}

main() {
	create_new_tmux_window
}
main
