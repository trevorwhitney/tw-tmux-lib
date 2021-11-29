#!/bin/bash

sha256="$(nix-prefetch-url \
	--unpack https://github.com/trevorwhitney/tmux-tw-lib/archive/main.tar.gz)"

cat <<EOF
{
  owner = "trevorwhitney";
  repo = "tmux-tw-lib";
  rev = "main";
  sha256 = "${sha256}";
}
EOF
