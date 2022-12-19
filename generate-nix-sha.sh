#!/usr/bin/env bash

sha256="$(nix-prefetch-url \
	--unpack https://github.com/trevorwhitney/tw-tmux-lib/archive/main.tar.gz)"

cat <<EOF
{
  owner = "trevorwhitney";
  repo = "tw-tmux-lib";
  rev = "main";
  sha256 = "${sha256}";
}
EOF
