#!/usr/bin/env bash
# Build and install the pinned Idris 2 (v0.8.0) plus its compiler API into
# ~/.idris2. Run inside WSL/Linux. Needs: chezscheme build-essential git libgmp-dev.
# Takes roughly 15-30 minutes: it bootstraps from Chez, then rebuilds itself.
set -euo pipefail
IDRIS_VERSION=v0.8.0
export PATH="$HOME/.idris2/bin:$PATH"
mkdir -p ~/src
cd ~/src
if [ ! -d Idris2 ]; then
  git clone --depth 1 --branch "$IDRIS_VERSION" https://github.com/idris-lang/Idris2.git
fi
cd Idris2
make bootstrap SCHEME=scheme -j"$(nproc)"
make install
# Rebuild with the bootstrapped compiler so the install is self-hosted.
make clean
make all -j"$(nproc)"
make install
make install-api
idris2 --version
echo 'Add to ~/.bashrc if not already there: export PATH="$HOME/.idris2/bin:$PATH"'
