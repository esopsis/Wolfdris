#!/usr/bin/env bash
# Count calls per generated function and per primitive while running a
# compiled program, then print the busiest ones.
# Usage: scripts/profile.sh build/exec/foo.wl [args...]
# Counting slows the program down several times; the counts are what
# matter. Lifted definitions are grouped by kind (<let>, <cont>, <alt>, ...).
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
file=$1; shift
out=${file%.wl}.prof.wl
cat "$repo/scripts/profile-prologue.wl" > "$out"
sed 's/^WolfdrisRT`runMain\[/profMain[/' "$file" >> "$out"
grep -q '^profMain\[' "$out" || { echo "no runMain call found in $file"; exit 1; }
"$repo/scripts/run-wl" "$out" "$@" 2>&1 | tr -d '\r'
