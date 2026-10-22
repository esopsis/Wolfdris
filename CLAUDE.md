# Wolfdris

Idris 2 with a Wolfram Language backend. Write Idris, get dependent types,
call the Wolfram library through typed wrappers.

The name: a mix of Wolfram and Idris

## What this is

```
.idr source
    ↓  Idris 2 compiler (unmodified — elaborator, unifier, totality, dependent types)
    ↓  intermediate representation
    ↓  Wolfdris codegen  ← we write this
Wolfram Language
    ↓
Wolfram Engine / Mathematica
```

We write two things: a **code generator** and a **wrapper library**. Everything
upstream of the IR comes free from Idris.

## What this is NOT

- Not a type checker for existing WL code. Nothing you've already written
  runs here.
- Not notebooks. You write `.idr` files in a text editor.
- Not "WL with types." The Wolfram part is a library you call from Idris.

## Decisions already made — don't relitigate without new information

### Why Idris 2 and not Haskell or PureScript

Idris 2 has a **documented, supported backend seam**: `Idris.Driver` exports
`mainWithCodegens`, taking a list of `(String, Codegen)`. Four IR stages are
available to consume (see below); chez, refc, racket, gambit and JavaScript
already exist as reference implementations.

- **Haskell**: GHC has no equivalent seam. Alternative backends (GHCJS,
  Asterius) were multi-year efforts and several died. Also lazy, so the
  runtime needs thunks, forcing and correct sharing. Worse target, better
  ecosystem — not worth the trade here.
- **PureScript**: strict, pluggable backends by design, easiest target of the
  three. Rejected because its type system is too weak for the dependent-type
  goal, which is the point of the project.

### Why not the earlier "typed WL" plan

A gradual type checker over existing WL code was the previous direction. It's
achievable but fundamentally unsound — any `ToExpression`, untyped `Import` or
symbol rebinding defeats it — and a checker over existing code must use
*permissive* signatures to avoid flagging working code, which means it catches
little. Dropped in favor of the stronger guarantee.

### Which IR: named case trees

The IR is what Idris hands the backend: types and proofs erased, pattern
matching compiled to case trees. The stages, highest to lowest:

| IR | Shape | Used by |
|---|---|---|
| **Named case trees** (`NamedCExp`) | lambdas, closures, named vars, constructor apps, `case` on tags | chez, racket, gambit, JS |
| Lambda-lifted | every lambda top-level + explicit captured env | — |
| ANF | lifted, every intermediate value `let`-bound | refc |
| VM code | registers, assignments, jumps | interpreter-style backends |

**Chosen: named case trees.** WL already has what this stage assumes —
`Function` gives closures with correct capture, `If`/`Which`/`Switch` give
case analysis — and the tail-call positions WL handles natively (see Risks)
are exactly the forms this stage emits. Revisit only if we need explicit
stack control (e.g. CPS for non-tail recursion).

### Codegen design (step 1, implemented 2026-10-21)

Code: `src/Wolfdris/{Codegen,Emit,Mangle,Foreign}.idr`, runtime
`support/wolfram/runtime.wl`.

- **One self-contained `.wl` per program, runtime inlined.** The compiler
  reads `wolfram/runtime.wl` via Idris's `readDataFile` (found through
  `IDRIS2_DATA`, set by `scripts/wolfdris`) and pastes it at the top. No
  run-time paths, no runtime/program version skew. Switch to
  `Needs["WolfdrisRT`"]` when we build the paclet.
- **Contexts:** generated symbols are fully qualified in `` WolfdrisGen` ``;
  the runtime lives in `` WolfdrisRT` `` (written inside
  `Begin`/`End`).
- **Shapes:** top-level function → `f[a_, b_] := body`; zero-arity
  definition → memoised constant `f := f = body`; `NmLam` →
  `Function[{x}, b]`; `NmLet` → `With`; closure application curried
  `e[a][b]`; constructors `WolfdrisRT`Con[tag, fields…]` (tag = name
  string when Idris gives none); con case → bind scrutinee once with
  `With`, `Switch` on `[[1]]`, fields via `With`; const case → `Switch` on
  literals; missing default → crash. `NmDelay`/`NmForce` →
  `Function[{}, e]` / `e[]`. All tail positions are in tail-safe forms.
- **Mangling:** our own injective `nameStr` (not `show`, which prints `DN`
  display names), then every non-`[A-Za-z0-9]` char → `$<hex>$`. Prefixes
  `f` (top-level), `v` (locals), `s` (scrutinee temps), `x` (foreign args).
- **Literals:** output is pure ASCII — strings use `\:XXXX` / `\|XXXXXX`
  for non-ASCII; `Char` is its integer code point.
- **Primitives: one SubValues table in the runtime.** Codegen emits
  `WolfdrisRT`op["Add", "Int64"][a, b]` generically; the runtime ends with
  a catch-all `op[keys__][___] := crash["not implemented: …"]`. A missing
  primitive therefore fails loudly — separate per-op symbols would stay
  unevaluated and give silent wrong answers. Revisit for speed later.
  `BelieveMe` and `Crash` are emitted directly.
- **Foreign table** (`Foreign.idr`, keyed by full Idris name) → runtime
  function, then a `wolfram:<Fn>` spec (called without world args), else a
  **compile-time error** naming the function and its specs. Chez doesn't
  map names — it really calls the C library — and several Prelude
  foreigns (`fastPack`/`fastUnpack`/`fastConcat`, `Data.Double`, clock,
  concurrency) have no `C:` spec at all, so a C-name table was rejected.
- **`%extern` prims:** `prim__codegen` → `"wolfram"`; others crash at run
  time ("extern not implemented").
- **`:exec` / `executeExpr`** not supported yet (throws with a hint).

Semantics copied from chez (v0.8.0 `support.ss` / `Scheme/Common.idr`):
`Neg` is **not** wrapped; `Mod` is never wrapped; casts String→Int parse a
number and truncate, else 0; Int→Char yields 0 for invalid code points;
`substr` clamps offset and length; string `<` compares code points.

### Primary reference: the in-tree JavaScript backend

Closer to us than chez: dynamic, strict target with no tail-call guarantee,
consuming `NamedCExp`. Its `Compiler.ES.TailRec` pass (tail recursion →
loops, including mutual recursion) is the prior art for step 4.

### Why wrappers instead of accepting shallow library types

WL functions return plain lists, so any value-dependent shape information is
lost at every library call:

```
Vect 5 Int  →  Select  →  Vect ??? Int
```

Fix: wrap, measure, re-establish the invariant as a dependent pair.

```idris
wlSelect : (a -> Bool) -> Vect n a -> (p ** Vect p a)
```

This is the deal the project is making: **we reuse WL's implementations and
write the types ourselves.** Good trade — `Solve` and `NDSolve` are decades of
work we could not reproduce; a wrapper around them is a few lines.

Write wrappers lazily, as programs need them. Five wrappers is enough for a
real program. Do NOT attempt a complete typed stdlib up front.

### Wrappers check where cheap, assert only where they must

Measuring makes a fact *checked*, not asserted: `wlSelect` measures `p`.
Where a wrapper claims a shape (`Sort` keeps length `n`), check it at runtime
and crash loudly on mismatch rather than `believe_me` it. This shrinks the
trusted base toward "the marshalling is correct" instead of "every wrapper is
correct".

**Polymorphic trap:** `Sort` on `Vect n a` with opaque `a` would sort by WL's
canonical order of the tagged-constructor representation, not Idris `Ord`.
Pass the Idris comparison closure in (`Sort[list, cmp]`), or restrict such
wrappers to primitive element types.

## Known limits — accept these, don't try to fix them

- **The trusted base is large.** Every wrapper asserts a fact the checker
  cannot verify. A wrong wrapper silently invalidates every proof built on it.
  Idris's own stdlib is small and verified; ours is large and asserted.
  (Runtime checks, above, reduce but don't remove this.)
- **Shape only.** A wrapper can assert `Sort` returns the same length. It
  cannot prove the result is *sorted* — WL builtins are black boxes with no
  source to analyze. Beyond shape, it's assertion all the way down.
- **Builtin totality is asserted, not proved.** Same reason. This is what
  Idris does for its own primitives, so it's legitimate — just trust, not
  proof.
- **No signed zero.** WL has no `-0.0` (`Sign[-0.]` is `0`). Accepted
  divergence from IEEE.
- **Slow.** Generated code will be far slower than chez — WL function-call
  overhead on every small Idris function. Fine: Idris orchestrates, heavy
  compute happens inside WL library calls. Don't optimize early.

## Build order

1. ✅ **Done 2026-10-21** — hello world plus 5 differential tests pass
   (`scripts/test.sh`). **Hello world end to end.** Minimal codegen, smallest possible runtime,
   one `.idr` file that compiles to `.wl` and prints. This is the real
   go/no-go checkpoint — a couple of weekends, and it proves the whole chain.
   Hidden hurdle: `putStrLn` reaches output via the prelude's `%foreign`
   declarations, which name C/Node functions. Every *reachable* foreign
   needs a spec our backend accepts, or compilation fails (that's how JS
   behaves). Either map known `C:` names (`idris2_putStr`, …) to runtime
   functions, as chez does, or attach `wolfram:` specs with `%foreign_impl`.
   API facts for this step: [docs/idris-backend-api.md](docs/idris-backend-api.md).
2. **Runtime library in WL.** The bulk of the work (see below).
3. **FFI + first wrappers.** Marshalling both directions; `Total`, `Map`,
   `Select`, `Length`, `Sort`.
4. **Tail call handling.** See risks.
5. **Grow the wrapper library** as real programs demand it. Mining notes:
   [docs/wrapper-mining.md](docs/wrapper-mining.md).

## The runtime is the bulk of the work

WL must host Idris's execution model:

- Tagged constructors and pattern matching on them
- Closures with correct environment capture
- Strings — source: the [Idris 2 backend cookbook](https://idris2.readthedocs.io/en/latest/backends/backend-cookbook.html),
  String section. Its warning against "diverging from the Idris
  representation" is about **nullability**: an Idris string always has a
  value, unlike host strings where NULL can be one. Its advice is a
  conversion layer between the host's strings and the runtime. For us: WL
  strings are never null, so native WL strings are fine inside the runtime;
  the conversion layer lives at the FFI boundary, where a WL call can return
  `Null`, `Missing[...]`, `$Failed` or a non-string — check and convert or
  crash there, never let it leak in as an Idris `String`. The cookbook also
  says strings are UTF-8 encoded at the FFI level, which matters only when
  marshalling bytes (e.g. `ByteArray`), not for WL's code-point strings.
  What must match beyond that is the *behavior* of the string primitives
  (`Length`, `Head`, `Tail`, `Index`, `Cons`, `Append`, `Reverse`, `Substr`).
- Primitive operations (plan below)
- `IO` and the effect world

None individually hard; a dozen-odd pieces that each must be right. Bugs here
surface as wrong answers in generated code, not clean errors.

**Namespace:** generated code and runtime live in their own context so Idris
names can't collide with `System\`` symbols (`List`, `Plus`, …). Keep runtime
data off heads with `Listable`/`Flat`/`Orderless` attributes.

### Primitives: one runtime function per (op, type)

Never emit raw WL arithmetic. Idris's primitive ops (`PrimFn`: `Add`, `Sub`,
`Mul`, `Div`, `Mod`, shifts, bitwise, comparisons, ~10 string ops, `Double`
math, casts, `BelieveMe`, `Crash`) and primitive types (`Int`, `Int8`–`Int64`,
`Bits8`–`Bits64`, `Integer`, `Double`, `Char`, `String`) are both finite.
Implemented as the `WolfdrisRT`op[...]` SubValues table in
`support/wolfram/runtime.wl` (see Codegen design). Step 1 covers all
integer arithmetic/comparisons, the 8 string ops and the int/Char/String
casts; shifts, bitwise ops and `Double` math still hit the
"not implemented" catch-all.

Behavior below verified on WL 15.0.1 (cloud) and 15.1.0 (local).

- **Fixed-width ints: compute exact, then wrap.** WL never overflows
  (`BitShiftLeft[2^62, 2]` is `2^64`).
  ```wolfram
  wrapU[n_][x_] := Mod[x, 2^n]                      (* Bits8..Bits64 *)
  wrapS[n_][x_] := Mod[x + 2^(n-1), 2^n] - 2^(n-1)  (* Int8..Int64, Int *)
  primAddInt64[a_, b_] := wrapS[64][a + b]
  ```
  `Integer` needs no wrapping.
- **Division: Euclidean, as in chez.** The remainder is always ≥ 0 — not
  truncating, not floor (they differ for negative divisors:
  `-7 div -2 = 4`, `-7 mod -2 = 1`). `Integer`/`Int`/`IntN` div is
  Euclidean then wrapped; `BitsN` div is plain quotient; `Mod` is always
  Euclidean. WL, checked against the chez code:
  `euclidMod[a_, b_] := Mod[a, Abs[b]]`,
  `euclidDiv[a_, b_] := (a - Mod[a, Abs[b]])/b`. Details:
  [docs/idris-backend-api.md](docs/idris-backend-api.md). Division by zero →
  runtime crash, not `ComplexInfinity`.
- **Double: the hard one.** WL has no IEEE special values:

  | Op | IEEE expects | WL gives |
  |---|---|---|
  | `1e308 * 10` | `Infinity` | bignum `1.0*^309` (silently leaves machine precision) |
  | `1.0 / 0.0` | `Infinity` | `ComplexInfinity` + message |
  | `0.0 / 0.0` | `NaN` | `Indeterminate` + message |
  | `sqrt(-1.0)` | `NaN` | `0. + 1.*I` |
  | `log(0.0)` | `-Infinity` | `Indeterminate` |
  | `-0.0` | signed zero | `0` |

  Plan: ordinary doubles stay WL machine reals; specials are runtime symbols
  (`dInf`, `dNegInf`, `dNaN`). Each `Double` primitive goes through a shared
  guard: handle special inputs, compute under `Quiet`, map any non-machine-real
  result (bignum, complex, `ComplexInfinity`, `Indeterminate`) to the right
  symbol. `show` for Double is hand-written — WL `InputForm` gives `1.*^21`
  where Idris prints `1e21`-style.
- **String/Char: mostly free.** WL strings are Unicode code points like
  Idris's (`StringLength["aα☃"]` is 3). String primitives map to `StringTake`,
  `StringJoin`, `StringReverse` etc. with bounds checks. `Char` is an integer
  code point (`ToCharacterCode["α"]` is `{945}`).

## Testing: differential against chez

Compile the same `.idr` with chez and with Wolfdris, diff stdout. Idris 2's
own `tests/` tree has expected outputs per backend — reuse it as a free
conformance suite. This is the main answer to four-suspect debugging.

Write the primitive edge-case programs first, one per primitive type:
`minBound`/`maxBound`, overflow, negative division, NaN/Infinity propagation,
`show` output. These are the silent-wrong-answer bugs.

## Risks

- **Recursion depth is a correctness issue, not a performance one.** Idris
  code is deeply recursive and assumes tail calls don't grow the stack.
  WL *partly* handles this — its evaluator rewrites some tail calls in place,
  counting against `$IterationLimit` instead of the stack. Measured (10^5
  countdown, `$IterationLimit = Infinity`; WL 15.0.1 cloud kernel, then
  re-verified identically on local WL 15.1.0 Windows `wolframscript`):

  | Tail call form | Result |
  |---|---|
  | direct `f[k_] := f[k-1]` | ✅ |
  | inside `If` | ✅ |
  | inside `With` | ✅ |
  | inside `Which` | ✅ |
  | inside `Switch` | ✅ |
  | pure `Function` | ✅ |
  | mutual recursion | ✅ |
  | after `CompoundExpression` (`(a; f[k-1])`) | ❌ recursion limit |
  | inside `Module` | ❌ recursion limit |
  | non-tail (`1 + len[r]`) | ❌ fails at depth 1024 |
  | 100,001-deep nested `cons[...]` data | ✅ builds and re-evaluates |

  So step 4 may mostly be a **codegen rule**: emit tail calls only in
  `If`/`Which`/`Switch`/`With`/`Function` position, never after `;` or
  inside `Module`, and raise `$IterationLimit`. **Non-tail recursion is the
  real limit** — raising `$RecursionLimit` just moves the crash to the C
  stack; needs CPS or an accepted cap. Invisible until it breaks on
  realistic input sizes.

  Hitting the limit yields `TerminatedEvaluation["RecursionLimit"]`, and on
  the local kernel it **aborted the whole top-level evaluation**, not just
  the failing subexpression — `Check` doesn't catch it. So in generated code
  a stack overflow kills the run; it can't be caught and recovered from.
- **Version churn.** The backend links against Idris compiler internals
  (`Core.TT`, `Compiler.Common`), which are not version-stable. Mitigations:
  pin the Idris version, keep the backend small, consume the lowest-level IR
  tolerable — simpler IRs churn less.

  **Pinned version: Idris 2 v0.8.0** (release tag, 2025-10-31). Pin release
  tags, not `main` commits: releases are roughly yearly, so upgrades are
  deliberate events, the docs (backend cookbook) match released code, and
  "build v0.8.0" is reproducible for contributors. Relevant v0.8.0 change:
  `CONS`/`NIL`/`JUST`/`NOTHING`-tagged constructors become
  `_builtin.CONS` etc., so the backend can reliably spot list/`Maybe` shapes
  for marshalling.

  **Upgrade policy:** move only to a new release, and only once the
  differential test suite passes on it. Never track `main`. Exception: a
  specific `main` fix we need — then pin that exact commit and record why
  here.

  **Verified 2026-10-21:** v0.8.0 builds cleanly under WSL Ubuntu 26.04
  with Chez Scheme 10.0.0 (see Toolchain → Setup).
- **Four-suspect debugging.** Codegen, runtime, FFI, or the Idris program
  itself. Build good tracing early; differential tests (above) localize most
  bugs.

## Toolchain

All inside WSL, from the repo (`/mnt/c/localDocs/Repos/Wolfdris`):

```bash
# one-time: Idris 2 v0.8.0 + compiler API (see Setup below)
scripts/build-idris.sh

# build the backend -> build/exec/wolfdris
scripts/build.sh

# compile a program -> build/exec/foo.wl (wrapper sets IDRIS2_DATA)
scripts/wolfdris --cg wolfram Foo.idr -o foo

# run it (Windows wolframscript from WSL)
"/mnt/c/Program Files/Wolfram Research/WolframScript/wolframscript.exe" -file "$(wslpath -w build/exec/foo.wl)"

# differential tests vs chez: all of tests/*/Main.idr, or name some
scripts/test.sh [name...]
```

Test layout: `tests/<name>/Main.idr`; the script compiles with chez and
Wolfdris, strips `\r`, diffs stdout. To add a test, add a directory.

**Gotchas found while building step 1:**
- The Idris driver **exits 0 when code generation fails** (type errors
  do exit nonzero). Check that the output file exists; `test.sh` does.
- `wolframscript` **merges the kernel's stderr into stdout**, so runtime
  crash messages appear in stdout (and in test diffs). Exit codes pass
  through (`Exit[3]` → 3).
- `wolframscript` output uses CRLF line endings on Windows.
- `-code` prints the final result (`Null`); `-file` doesn't.
- From PowerShell 5.1, embedded `"` in native-exe arguments get stripped;
  call `wolframscript.exe -code '...'` from bash instead.

### Setup (verified 2026-10-21)

Windows host, everything Idris runs in **WSL 2 (Ubuntu 26.04)**:

- Packages: `chezscheme build-essential git libgmp-dev` (Chez Scheme 10.0.0
  builds Idris 2 v0.8.0 fine).
- Idris: `scripts/build-idris.sh` clones v0.8.0 to `~/src/Idris2`,
  bootstraps from Chez, self-hosts, and runs `make install-api`. Installs to
  `~/.idris2` (on `PATH` via `~/.bashrc`). The source tree is readable from
  Windows at `\\wsl.localhost\Ubuntu\home\<user>\src\Idris2`.
- **Wolfram: use the Windows install from WSL** — no Linux Wolfram needed.
  `wolframscript.exe` is at
  `/mnt/c/Program Files/Wolfram Research/WolframScript/wolframscript.exe`;
  pass it Windows paths via `wslpath -w` (Linux files become
  `\\wsl.localhost\...`, which works). Local version: WL 15.1.0. The Wolfram
  MCP kernel is 15.0.0 — test generated code with `wolframscript`, not MCP.
- Build in the Linux filesystem (`~/...`), not `/mnt/c` — much faster.
- Driving WSL from PowerShell: quoting `bash -c '...'` through PowerShell
  breaks easily. Write a script file and run
  `wsl.exe -d Ubuntu -- bash /mnt/c/.../script.sh`; set `$env:WSL_UTF8='1'`
  so `wsl.exe` output isn't UTF-16.

## Distribution

Asymmetric, and favorably so:

- **Running compiled output**: needs only Wolfram Engine + the generated `.wl`
  + the runtime library. No Idris, no Chez Scheme, nothing to link.
- **Target: ship as a paclet.** Wrap generated code + runtime, expose entry
  points, and WL users call it from a normal notebook without knowing Idris
  was involved. This is the version where the project has users beyond us.
  Needs marshalling at the boundary so callers get ordinary lists and numbers,
  not tagged constructors.
- **Building from source**: needs the full Idris chain. Contributors do this;
  users don't.

## Conventions

- Wolfram Language unless specified otherwise.
- Append design decisions to this file as they're made. Its value is that it
  accumulates — every session starts cold from what's written here.
- Reference material for later build steps goes in `docs/` and is linked
  from here, to keep this file focused.
