#!/usr/bin/env bash
# Build the Wolfdris compiler (build/exec/wolfdris). Run inside WSL/Linux.
set -euo pipefail
export PATH="$HOME/.idris2/bin:$PATH"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
idris2 --build wolfdris.ipkg
# The wrapper library (package "wolfram"), installed into ~/.idris2 so
# programs can use it with -p wolfram. Built from clean: Idris doesn't
# rebuild importers when only an operator's fixity changes, so a stale
# module can bring back the old fixity (seen with ^ in Wolfram.Symbolic).
( cd lib && rm -rf build && idris2 --install wolfram.ipkg )
