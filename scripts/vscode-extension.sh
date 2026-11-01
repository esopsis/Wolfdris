#!/usr/bin/env bash
# Build the VS Code highlighting extension: regenerate the list of library
# names from lib/ and package editor/vscode/ as a .vsix.
# Install it (from Windows, or VS Code's terminal) with
#   code --install-extension editor/vscode/build/wolfdris-highlight.vsix
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ext=$repo/editor/vscode
prelude=${IDRIS2_SRC:-$HOME/src/Idris2}/libs/prelude
[ -d "$prelude" ] || { echo "Idris Prelude source not found at $prelude (set IDRIS2_SRC)"; exit 1; }
mkdir -p "$ext/build"
python3 "$ext/gen_names.py" "$repo" "$prelude" "$ext/build/names.json"
python3 "$ext/package_vsix.py" "$ext" "$ext/build/names.json" "$ext/build/wolfdris-highlight.vsix"
