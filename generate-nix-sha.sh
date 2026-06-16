#!/usr/bin/env bash

set -euo pipefail

REPO="trevorwhitney/tw-tmux-lib"
BRANCH="main"

rev="$(git ls-remote "https://github.com/${REPO}" "refs/heads/${BRANCH}" | cut -f1)"

sha256="$(nix-prefetch-url \
	--unpack "https://github.com/${REPO}/archive/${rev}.tar.gz")"

cat <<EOF
rev = "${rev}";
sha256 = "${sha256}";
EOF
