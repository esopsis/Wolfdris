#!/usr/bin/env bash
# Build a paclet from an Idris library program: one whose main is
# Wolfram.Export.library [...]. Run inside WSL/Linux after scripts/build.sh.
# Usage: scripts/paclet.sh Main.idr Name outdir [idris options...]
# Writes outdir/Name/PacletInfo.wl and outdir/Name/Kernel/Name.wl; in WL:
#   PacletDirectoryLoad["outdir/Name"]; Needs["Name`"]
set -euo pipefail
export PATH="$HOME/.idris2/bin:$PATH"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ $# -ge 3 ] || { echo "usage: $0 Main.idr Name outdir [idris options...]"; exit 2; }
src=$1 name=$2 out=$3; shift 3
dir="$out/$name"
build="$out/.build-$name"
mkdir -p "$dir/Kernel" "$build"
"$repo/scripts/wolfdris" -p wolfram "$@" --cg wolfram \
  --directive library --directive "package=$name" \
  --build-dir "$build" "$src" -o "$name"
# The Idris driver exits 0 even when code generation fails
[ -f "$build/exec/$name.wl" ] || { echo "paclet.sh: compiling $src failed"; exit 1; }
cp "$build/exec/$name.wl" "$dir/Kernel/$name.wl"
cat > "$dir/PacletInfo.wl" <<EOF
PacletObject[<|
  "Name" -> "$name",
  "Version" -> "0.1.0",
  "Description" -> "Built from Idris 2 by Wolfdris",
  "Extensions" -> {{"Kernel", "Root" -> "Kernel", "Context" -> {"$name\`"}}}
|>]
EOF
echo "paclet $name: $dir"
