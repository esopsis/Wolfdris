#!/usr/bin/env bash
# Differential tests: compile each tests/<name>/Main.idr with chez and with
# Wolfdris, run both, and diff stdout. Run inside WSL/Linux after
# scripts/build.sh. Usage: scripts/test.sh [name...]
set -uo pipefail
export PATH="$HOME/.idris2/bin:$PATH"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WS=${WOLFRAMSCRIPT:-"/mnt/c/Program Files/Wolfram Research/WolframScript/wolframscript.exe"}

if [ $# -gt 0 ]; then names=("$@"); else
  names=(); for d in "$repo"/tests/*/; do names+=("$(basename "$d")"); done
fi

pass=0; fail=0; failed=()
for name in "${names[@]}"; do
  dir="$repo/tests/$name"
  cd "$dir" || { echo "FAIL $name (no such test)"; fail=$((fail+1)); failed+=("$name"); continue; }
  rm -rf build
  if ! idris2 --cg chez Main.idr -o chez_main > build_chez.log 2>&1; then
    echo "FAIL $name (chez compile)"; cat build_chez.log
    fail=$((fail+1)); failed+=("$name"); continue
  fi
  ./build/exec/chez_main > expected.out 2>&1
  # The Idris driver exits 0 when code generation fails, so also check
  # that the output file exists.
  if ! "$repo/scripts/wolfdris" --cg wolfram Main.idr -o main > build_wl.log 2>&1 \
     || [ ! -f build/exec/main.wl ]; then
    echo "FAIL $name (wolfdris compile)"; cat build_wl.log
    fail=$((fail+1)); failed+=("$name"); continue
  fi
  "$WS" -file "$(wslpath -w build/exec/main.wl)" 2>&1 | tr -d '\r' > actual.out
  if diff -u expected.out actual.out > diff.out; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL $name (output differs)"; cat diff.out
    fail=$((fail+1)); failed+=("$name")
  fi
done
echo "---- $pass passed, $fail failed ${failed[*]:+(${failed[*]})}"
[ "$fail" -eq 0 ]
