#!/bin/bash

tmux_socket() {
	echo "$TMUX" | cut -d',' -f1
}

main() {
  tmpDir=$(mktemp -d)
	TMUX="" tmux -S "$(tmux_socket)" new-window -n "tmp"
  tmux send -t tmp "cd $tmpDir" ENTER
  tmux send -t tmp "vtemp" ENTER
}
main
