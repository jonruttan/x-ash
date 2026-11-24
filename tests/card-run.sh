#!/bin/sh
# card-run.sh FILE -- run one script of docs/card.md, as the card check asks.
# It runs in a scratch directory, so a script that writes a file or matches
# names writes and matches there.
dir=$(mktemp -d) || exit 1
trap 'rm -rf "$dir"' EXIT
cd "$dir" && "${X:-x}" -l ash -- "$1"
