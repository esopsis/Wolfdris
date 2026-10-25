#!/usr/bin/env bash
# Differential tests: compile each tests/<name>/Main.idr with chez and with
# Wolfdris, run both, and diff stdout. A test with a tests/<name>/expected
# file is a golden test instead: wolfram only (with the wolfram package),
# diffed against that file. A test with a driver.wl is a paclet test: Main.idr
# is built as each paclet named in tests/<name>/paclets, and driver.wl's
# output is diffed against expected. Run inside WSL/Linux after
# scripts/build.sh.
# Usage: scripts/test.sh [name...]
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
  # Optional tests/<name>/input is piped to both programs as stdin.
  input=/dev/null; [ -f input ] && input=input
  if [ -f driver.wl ]; then
    # Paclet test: build Main.idr as the paclets named in `paclets` (into
    # build/paclet), then run driver.wl, which loads and calls them.
    ok=1; : > build_wl.log
    while read -r p; do
      [ -n "$p" ] || continue
      "$repo/scripts/paclet.sh" Main.idr "$p" build/paclet >> build_wl.log 2>&1 || ok=0
    done < paclets
    if [ "$ok" -eq 0 ]; then
      echo "FAIL $name (paclet build)"; cat build_wl.log
      fail=$((fail+1)); failed+=("$name"); continue
    fi
    WOLFRAMSCRIPT="$WS" "$repo/scripts/run-wl" driver.wl < "$input" 2>&1 | tr -d '\r' > actual.out
    if diff -u expected actual.out > diff.out; then
      echo "PASS $name"; pass=$((pass+1))
    else
      echo "FAIL $name (output differs)"; cat diff.out
      fail=$((fail+1)); failed+=("$name")
    fi
    continue
  fi
  if [ -f expected ]; then
    # Golden test: programs using the wolfram package can't run on chez.
    cp expected expected.out
    pkgs=(-p wolfram)
  else
    if ! idris2 --cg chez Main.idr -o chez_main > build_chez.log 2>&1; then
      echo "FAIL $name (chez compile)"; cat build_chez.log
      fail=$((fail+1)); failed+=("$name"); continue
    fi
    ./build/exec/chez_main < "$input" > expected.out 2>&1
    pkgs=()
  fi
  # The Idris driver exits 0 when code generation fails, so also check
  # that the output file exists.
  if ! "$repo/scripts/wolfdris" "${pkgs[@]}" --cg wolfram Main.idr -o main > build_wl.log 2>&1 \
     || [ ! -f build/exec/main.wl ]; then
    echo "FAIL $name (wolfdris compile)"; cat build_wl.log
    fail=$((fail+1)); failed+=("$name"); continue
  fi
  WOLFDRIS_TIMEOUT=${WOLFDRIS_TIMEOUT:-900} WOLFRAMSCRIPT="$WS" \
    "$repo/scripts/run-wl" build/exec/main.wl < "$input" 2>&1 | tr -d '\r' > actual.out
  if diff -u expected.out actual.out > diff.out; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL $name (output differs)"; cat diff.out
    fail=$((fail+1)); failed+=("$name")
  fi
done
echo "---- $pass passed, $fail failed ${failed[*]:+(${failed[*]})}"
[ "$fail" -eq 0 ]
