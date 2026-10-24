#!/usr/bin/env bash
# Build the Wolfdris compiler (build/exec/wolfdris). Run inside WSL/Linux.
set -euo pipefail
export PATH="$HOME/.idris2/bin:$PATH"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
idris2 --build wolfdris.ipkg
# The wrapper library (package "wolfram"), installed into ~/.idris2 so
# programs can use it with -p wolfram
( cd lib && idris2 --install wolfram.ipkg )
