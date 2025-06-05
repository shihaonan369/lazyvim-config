#!/bin/bash

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <ascii_txt_dir> [fps=24] [loop=true|false]"
  exit 1
fi

ASCII_DIR="$1"
FPS="${2:-24}"
LOOP="${3:-true}"
DELAY=$(awk "BEGIN {print 1/$FPS}")

play_once() {
  for frame in $(ls "$ASCII_DIR"/*.txt | sort); do
    clear
    cat "$frame"
    sleep "$DELAY"
  done
}

if [ "$LOOP" = "true" ]; then
  while true; do
    play_once
  done
else
  play_once
fi
