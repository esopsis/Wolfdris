#!/usr/bin/env bash
# Run Idris 2's own test suite against the wolfram backend.
# Usage: scripts/conformance.sh [--only "chez/chez001 base/data_list001"] [--threads N]
# Run inside WSL after scripts/build.sh. Results: build/conformance/failures,
# compared against conformance/baseline.txt (the tests expected to fail).
set -uo pipefail
export PATH="$HOME/.idris2/bin:$PATH"
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src=${IDRIS2_SRC:-"$HOME/src/Idris2/tests"}
work="$repo/build/conformance"
only=""; threads=4
while [ $# -gt 0 ]; do
  case "$1" in
    --only) only=$2; shift 2 ;;
    --threads) threads=$2; shift 2 ;;
    *) echo "unknown argument: $1"; exit 2 ;;
  esac
done

# 1. Fresh copy, so the Idris checkout stays pristine.
rm -rf "$work/tests"; mkdir -p "$work/tests"
for d in testutils.sh chez allschemes allbackends base prelude contrib idris2; do
  cp -r "$src/$d" "$work/tests/"
done
cd "$work/tests" || exit 1

# 2. Prune to tests that run a program with our backend.
drop() { rm -rf "$1"; }
while read -r dir; do
  run="$dir/run"
  if grep -q -- '--cg' "$run"; then drop "$dir"; continue; fi
  if ! grep -qE '^\s*run |--exec|:exec|-o |build/exec' "$run" \
     && ! { [ -f "$dir/input" ] && grep -q ':exec' "$dir/input"; }; then
    drop "$dir"; continue
  fi
  if grep -q '_app' "$run" \
     || [ -n "$(find "$dir" \( -name '*.c' -o -name '*.h' -o -name '*.ss' -o -name '*.scm' -o -name '*.rkt' \) -print -quit)" ] \
     || grep -rqE 'import +(System\.Concurrency|System\.Future|Network\.|System\.Signal)' "$dir" --include='*.idr'; then
    drop "$dir"; continue
  fi
done < <(find . -name run -printf '%h\n' | sort)
grep -vE '^\s*(#|$)' "$repo/conformance/exclude.txt" | awk '{print $1}' | while read -r t; do drop "$t"; done
echo "tests after pruning: $(find . -name run | wc -l)"

# 3. Build the runner and run it. The Idris runner has no per-test timeout,
# so a hanging program would block the whole run; cap each one.
export WOLFDRIS_TIMEOUT=${WOLFDRIS_TIMEOUT:-300}
( cd "$repo/conformance" && idris2 --build runner.ipkg > /dev/null ) || exit 1
args=("$repo/scripts/wolfdris" --cg wolfram --timing --threads "$threads" --failure-file "$work/failures")
[ -n "$only" ] && args+=(--only "$only")
"$repo/conformance/build/exec/runtests" "${args[@]}"

# 4. Compare with the baseline (only meaningful for full runs).
if [ -z "$only" ] && [ -f "$repo/conformance/baseline.txt" ]; then
  sort -u "$work/failures" > "$work/failures.sorted"
  # Only tests that ran this time (excluded/pruned ones aren't "passing").
  find . -name run -printf '%h\n' | sed 's|^\./||' | sort -u > "$work/ran.sorted"
  grep -vE '^\s*(#|$)' "$repo/conformance/baseline.txt" | sort -u \
    | comm -12 - "$work/ran.sorted" > "$work/baseline.sorted"
  echo "---- newly failing (regressions):"; comm -13 "$work/baseline.sorted" "$work/failures.sorted"
  echo "---- newly passing:"; comm -23 "$work/baseline.sorted" "$work/failures.sorted"
fi
