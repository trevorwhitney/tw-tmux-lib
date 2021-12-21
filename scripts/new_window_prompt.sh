#!/bin/bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

main() {
	tmux command -p "new window name:" "run '$CURRENT_DIR/new_window.sh \"%1\"'"
}
main
