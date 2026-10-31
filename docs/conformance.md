# Conformance: Idris 2's own test suite under the wolfram backend

`scripts/conformance.sh` runs the program-running tests from Idris 2
v0.8.0's `tests/` tree against Wolfdris and compares with each test's
`expected` output (written for chez, which we mimic).

```bash
scripts/build.sh                                  # backend first
scripts/conformance.sh                            # full run, ~10 min
scripts/conformance.sh --only "chez/chez001 base/data_list001"
```

Results land in `build/conformance/` (`failures`, and each test's `output`
next to its `expected` under `build/conformance/tests/<test>/`). A full run
ends by comparing the failures with `conformance/baseline.txt`: anything
newly failing is a regression.

## How it works

- `scripts/conformance.sh` copies `chez`, `allschemes`, `allbackends`,
  `base`, `prelude`, `contrib` and `idris2` (plus `testutils.sh`) from
  `~/src/Idris2/tests` into `build/conformance/tests`, so the Idris checkout
  stays pristine, then prunes:
  - tests whose `run` contains `--cg` (they force chez/node and would
    pass without exercising us);
  - tests that never run a program (type checking / REPL evaluation only:
    backend-independent);
  - tests shipping C/Scheme/Racket sources or reading generated chez code;
  - tests importing threads, network or signal modules;
  - everything in `conformance/exclude.txt` (with reasons).
- `conformance/Runner.idr` is a `Test.Golden` runner with one
  `codegen = Default` pool per surviving directory, run as
  `runtests scripts/wolfdris --cg wolfram`, so every `run` script's
  `idris2 …` / `run X.idr` (= `--exec main`) uses our backend.
- Each program run is capped by `WOLFDRIS_TIMEOUT` (300 s; the Idris
  runner has none, and one hang blocked a whole run for 90 minutes).

## Status (2026-10-30, after the op-table dispatch fix)

**99 / 108 pass**, no regressions. History: 77 / 123 (first baseline),
96 / 108 (2026-10-22, first fix round), 97 / 108 (2026-10-24, step 4).

The op-table dispatch fix (CLAUDE.md "Speed": primitives reached by a
hashed lookup instead of a scan of 364 rules) brought `chez/newints` and
`prelude/bind001` under the 300 s limit.

Fixed in the first round: `executeExpr` (`--exec`, REPL `:exec`); `-o`
launcher executables; memoised top-level `Lazy` constants; arithmetic
`ShiftR` on negatives; chez's crash message formats; `MkNmError`
definitions; files (C stdio semantics), directories, exit, args, env,
clock, errno, terminal size; argument passing around a `wolframscript` bug.

Step 4 (CPS + closure conversion) removed the recursion-depth failures:
`contrib/perf001` now passes; the other three no longer overflow but are
too slow for the 300 s per-program limit.

### Remaining failures (9), by bucket

| Bucket | Tests | What it needs |
|---|---|---|
| Too slow (300 s limit) | `contrib/json_001` (`[0 .. 55295]` chars, each round-tripped through JSON) | General codegen speed. `chez/newints` and `prelude/bind001` left this bucket with the op-table dispatch fix (2026-10-30). Older notes: Measured 2026-10-24 (CLAUDE.md "Speed"): linear, per-call overhead plus ~14 s kernel start. After the Int-wrap fix and inlined primitives, estimated full runs: newints ~340 s, json_001 ~530 s; `prelude/bind001` (12.5M list cells) is borderline: 290–330 s against the 300 s limit, so it passes on some runs (kept in the baseline). Next lever: direct style for non-recursive leaf functions (deferred, with readable mode). Was the recursion bucket before step 4. |
| `Data.Buffer` | `chez/buffer001`, `chez/chez004`, `base/system_file_copyFile`, `contrib/system_directory_tree_copyDir` | ~28 scheme-only buffer foreigns (`Data.Buffer`, `System.File.Buffer`): a mutable byte store with typed get/set and file read/write. Mechanical. |
| Processes | `base/system_run`, `base/system_file_popen`, `allbackends/popen2`, `idris2/misc/golden001` (its runner calls `system`) | `system`/`popen`/`popen2`. Design question first: the kernel runs on Windows, the user's shell is WSL — whose shell should `system "echo hi"` use? |

### Excluded on purpose

See `conformance/exclude.txt`. In short: C FFI, network, threads, tests
that inspect chez's generated code or chez-specific errors, chez's
`lazy=weakMemo` directive and GC foreign, and three host differences —
`-0.0` (no signed zero in WL), processor count and OS name (Windows
kernel vs WSL), and `currentDir` (a Windows path).
