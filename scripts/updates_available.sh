#!/bin/bash

qalc -t "$(apt list --upgradable | head -n -1 | wc -l) + $(flatpak remote-ls --updates | wc -l)"
