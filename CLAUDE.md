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

### Readable WL output: deferred, not ruled out

A possible later mode: emit idiomatic WL for the subset of functions where
it's achievable (first-order, non-monadic, simple types), faithful output
for everything else, with the output marking which is which. Not a goal for
steps 1–4. Recorded here so it isn't assumed impossible.

**The irreversible decision already went the right way.** Named case trees
is the highest-level IR, so more of the original program's shape survives
than in the lower IRs, which discard it. **But only partly:** by NamedCExp,
Idris has already flattened nested patterns into case trees, inlined small
functions, turned interfaces into dictionary passing, lifted
`where`/`case`/`with` blocks into separate top-level functions (`Nested`,
`CaseBlock`, `WithBlock` names), turned `Nat` into `Integer`, and turned
`IO` into explicit world-token passing. So first-order code like `sumList`
can come out close to the source; anything using `map`/`show`/`>>=` shows
dictionary plumbing, and **`IO` code will essentially never be idiomatic**.
That's why the scope is "first-order, non-monadic".

**Prerequisites already in place:**
- Equivalence checking: `scripts/test.sh` (differential vs chez) and, more
  strongly, `scripts/conformance.sh` (Idris's own suite). Running the
  conformance suite with readable mode on exercises a second emit path
  against ~100 real programs. Two translations of one function must behave
  identically, forever; these are that harness.
- ~~Emitted shapes are already half-idiomatic~~ — **no longer true after
  step 4 (2026-10-24)**: output is now full CPS with closure conversion and
  no `With` (see "CPS + closure conversion"); every function takes a
  continuation and every binding is a call to a lifted definition. That's
  far from readable. A readable mode would emit **direct style** for
  provably non-recursive, closure-free functions — which is also the
  natural performance optimisation for CPS, so the two share a hook. But
  readable direct style must still avoid `With` over bodies holding large
  values (see the WL substitution facts), and tail calls must never follow
  `;`.

**The three hooks, when we want it:**
1. `Mangle.idr` — readable mode: leave names alone where they're already
   valid, collision-free WL symbols. Catch: many locals are
   machine-generated (`{arg:0}`, `{eta:0}`), and the original user names
   aren't always in the IR, so readable arguments may need name recovery.
2. Representation — **decided (2026-10-23): keep `Con` cells as the internal
   representation** so cons and rest stay O(1). WL lists exist only at the
   boundary (paclet entry points, FFI), converted once in O(n). Making
   `List` a WL list internally would turn ordinary recursive list code
   O(n²) (`Prepend`/`Rest` copy). So readable mode does **not** get real
   lists, and the paclet marshalling work is *not* shared with it.
   `JUST`/`NOTHING` at the boundary need their own rule: `Missing[]` can't
   distinguish `Just Nothing` from `Nothing` for nested `Maybe`.
3. Un-currying — calls to top-level functions are **already** `f[a, b, k]`;
   only closures are curried (`c[a, k1]`, then `c'[b, k]`). Un-currying closures is the hard
   part: it needs proof that every call site applies all the arguments. So
   this hook is smaller than it looks, and harder.

**Before starting, measure the gap cheaply:** take 3 small programs,
hand-write the ideal WL for each, and compare with current output.

**Why deferred:** readability has no natural stopping point and is more
immediately rewarding than runtime bugs or tail calls. The failure mode is
beautiful output for pure list functions and no working `IO`. Revisit after
step 4.

**Not in scope:** types in the output. They're erased at the IR; the
generated code carries no type information and won't.

### Codegen design (step 1, implemented 2026-10-21)

Code: `src/Wolfdris/{Codegen,Emit,Mangle,Foreign}.idr`, runtime
`support/wolfram/runtime.wl`.

- **One self-contained `.wl` per program, runtime inlined.** The compiler
  reads `wolfram/runtime.wl` via Idris's `readDataFile` (found through
  `IDRIS2_DATA`, set by `scripts/wolfdris`) and pastes it at the top. No
  run-time paths, no runtime/program version skew. Paclets keep it inlined
  too, under per-paclet contexts (see "Paclets"), rather than a shared
  `Needs["WolfdrisRT`"]`: two paclets never disagree about the runtime.
- **Contexts:** generated symbols are fully qualified in `` WolfdrisGen` ``;
  the runtime lives in `` WolfdrisRT` `` (written inside
  `Begin`/`End`).
- **Shapes:** *(superseded by step 4 — see "CPS + closure conversion"
  below)* constructors `WolfdrisRT`Con[tag, fields…]` (tag = name string
  when Idris gives none); con case → `Switch` on `[[1]]`; const case →
  `Switch` on literals; missing default → crash.
- **Mangling:** our own injective `nameStr` (not `show`, which prints `DN`
  display names), then every non-`[A-Za-z0-9]` char → `$<hex>$`. Prefixes
  `f` (top-level), `v` (locals), `s` (scrutinee temps), `x` (foreign args).
- **Literals:** output is pure ASCII — strings use `\:XXXX` / `\|XXXXXX`
  for non-ASCII; `Char` is its integer code point.
- **Primitives: one SubValues table in the runtime.** Codegen emits
  `WolfdrisRT`op["Add", "Int64"][a, b]` generically; the runtime ends with
  a catch-all `op[keys__][___] := crash["not implemented: …"]`. A missing
  primitive therefore fails loudly — separate per-op symbols would stay
  unevaluated and give silent wrong answers. Ops that need no wrapping
  are inlined as plain WL instead (see "Speed").
  `BelieveMe` and `Crash` are emitted directly.
- **Foreign table** (`Foreign.idr`, keyed by full Idris name) → runtime
  function, then a `wolfram:<Fn>` spec (called without world args), else a
  **compile-time error** naming the function and its specs. Chez doesn't
  map names — it really calls the C library — and several Prelude
  foreigns (`fastPack`/`fastUnpack`/`fastConcat`, `Data.Double`, clock,
  concurrency) have no `C:` spec at all, so a C-name table was rejected.
- **`%extern` prims** (`extPrim` in `Emit.idr`, arg shapes from JS's
  `jsPrim`): `prim__codegen` → `"wolfram"`, `prim__os`, IORefs, arrays,
  `prim__getChar`; others crash at run time ("extern not implemented").
  IORefs/arrays are inert handles `Ref[id]`/`Arr[id]` into runtime-owned
  associations (never freed).
- **stdin:** `wolframscript` gives `-file` scripts no stdin stream
  (`"stdin"` can't be opened, `InputString[]` returns `EndOfFile`); all of
  stdin arrives **up front** in `$ScriptInputString`, as raw UTF-8 bytes
  one per character. The runtime decodes it once and reads lines/chars from
  that buffer. Consequence: piped input works, **interactive
  prompt-then-read programs don't**.
- **Running programs.** `executeExpr` (`--exec`, REPL `:exec`) writes
  `tmpDir/_tmp_wolfdris.wl` and runs `$WOLFDRIS_RUNNER file` (default
  `wolframscript -file`). `-o foo` writes `build/exec/foo.wl` **and** a
  launcher `build/exec/foo` (sh, uses `$WOLFDRIS_RUNNER` or the runner
  known at compile time), like other backends' executables.
  `scripts/wolfdris` sets `WOLFDRIS_RUNNER=scripts/run-wl`, which converts
  the path for Windows `wolframscript.exe`, applies `WOLFDRIS_TIMEOUT`,
  and passes program arguments in `WOLFDRIS_ARGS` (forwarded via
  `WSLENV`): **`wolframscript` silently drops script arguments starting
  with `-` and everything after them**, with no escape. The runtime
  decodes `WOLFDRIS_ARGS` (base64 of NUL-terminated UTF-8) for `getArgs`.
- **I/O and system foreigns** (`Foreign.idr` table → runtime): files with
  C stdio semantics (read-mode files loaded whole into a buffer; `readLine`
  keeps `\n`, `""` at EOF; EOF flag only set when a read hits the end;
  `fileErrno` codes as `idris_file.c`), stdin as handle 0, directories,
  exit, args, env (in-process; WSL env vars don't reach the Windows kernel
  except via `WSLENV`), clocks, errno/strerror, terminal size (0).
  Pointers: a `Ptr String` is the string; NULL is `nullPtr`.
- **Runtime heads must not be `System`` symbols.** Inside
  `Begin["WolfdrisRT`"]`, a name like `File` or `Clock` silently resolves
  to the built-in — use `FileH`, `ClockH`, etc. Check new heads with
  `Names["System`" <> name]`.
- **Crashes** match chez: compiler-generated (`NmCrash`) print the bare
  message, `idris_crash` prints `ERROR: ` + message; both on stdout, exit 1.
- **Top-level `Lazy` constants** (`MkNmFun [] (NmDelay …)`) memoise their
  forced value (`f$lazy`), like chez's `(define f (delay …))`. Other lazy
  values are not memoised (chez default; `lazy=weakMemo` is chez-only).

Semantics copied from chez (v0.8.0 `support.ss` / `Scheme/Common.idr`):
`Neg` is **not** wrapped; `Mod` is never wrapped; casts String→Int parse a
number and truncate, else 0; Int→Char yields 0 for invalid code points;
`substr` clamps offset and length; string `<` compares code points.

### CPS + closure conversion (step 4, implemented 2026-10-24)

**Problem.** WL caps non-tail recursion (`$RecursionLimit`, then the
Windows C stack: past ~50k–100k levels the kernel dies with 0xC00000FD).
Ordinary Idris library code is non-tail recursive (`[a..b]` via
`takeUntil`, `foldr`, `traverse_`/`for_`, `sort`, `zip`, `lines`, `Nat`
comparisons), so `[1..5000]` used to fail. Worse, hitting the limit does
**not** stop the program: `TerminatedEvaluation["RecursionLimit"]` comes
back as a value and evaluation carries on (→ garbage, "unmatched case").

**Decision (with the user): full CPS + our own closure conversion**, in
`Emit.idr`:
- Every function and closure takes a continuation; every call is a tail
  call (WL handles those natively). Depth is unlimited: verified 200,000+
  deep (`tests/deeprec`).
- One-pass CPS with a meta-continuation (`Obj k` / `Meta m`): no
  administrative continuations; `reify` makes a real one only when needed.
- **Closure conversion**: lambdas, thunks and continuations are lifted to
  top-level definitions taking their captured variables first; closure
  values are data, `WolfdrisRT`Clo[code, captured…]`, applied by one
  runtime rule `Clo[f_, c___][a___] := f[c, a]`.
- **No `With` in generated code.** Every binding (let, case fields,
  scrutinee, join point, effect result) is a direct call to a lifted
  definition with the values as parameters (`liftCall`).
- **Every binder gets a fresh WL symbol** (`localSym x <> "$N"`), tracked
  by the dynamic scope stack (`InScope`); captures use a whole-symbol test
  (`occursSym`).
- Result: same speed as the old direct style on our benchmark (34–38 s vs
  38–40 s), linear scaling (64,000-element `foldr`/ranges in ~7 s).
- Rejected: selective CPS (can't see recursion through closures at run
  time, e.g. `IO` `for_`); Idris's lambda-lifted IR (doesn't cover our CPS
  continuations, so two mechanisms; de Bruijn variables; reopens the IR
  decision).

**Why each piece — WL facts found the hard way (WL 15.0/15.1):**
- **`With` and `Function` application walk the substituted body,
  including values already embedded in it, whenever those values mention
  many distinct symbols.** With 1–2 distinct symbols WL skips them (some
  per-expression symbol summary); with 400 the cost was linear in the
  value's size. Generated code always has hundreds (every `lamN`/`contN`),
  so `With` over a body holding a list / continuation chain / dictionary
  made loops quadratic. Pattern substitution in a `SetDelayed` definition
  only walks its own small template: constant at any value size. Hence
  `liftCall` instead of `With`, and closures as data instead of `Function`.
  The same effect made plain CPS continuations, `IO` `for_` and ranges
  quadratic before each fix.
- **Pattern substitution doesn't respect inner scoping.** A captured value
  replaces *every* occurrence of the pattern variable in the lifted body,
  including an inner binder of the same name (`With[{5050 = …}]`). Idris's
  IR reuses local names in nested scopes → fresh symbol per binder.
- **Over-capture is not harmless.** A substring capture test matched
  `WolfdrisGen`k` inside `WolfdrisGen`k581`, so closures (e.g. `IO`
  actions) kept their enclosing continuations alive; `traverse_` became
  *exponential*. Whole-symbol test fixed it.
- Name-dependence is real and misleading: one With variable name was fast,
  another slow, same code — don't trust micro-benchmarks that use 1–2
  symbols.

**Runtime side** (`runtime.wl`): `idK`, `Clo` rule, and the backstop —
`$RecursionLimit = 10000`, a `Message` handler that `Abort[]`s on
`$RecursionLimit::reclim`, and `runMain` (`CheckAbort` → `ERROR: stack
overflow (recursion too deep)`, exit 1; `Exit` can't be called from inside
the handler under wolframscript). `$Messages = {}` unless `WOLFDRIS_DEBUG`
is set (WL messages would land in program output). `runMain` also enforces
`WOLFDRIS_TIMEOUT` with `TimeConstrained`: killing wolframscript from WSL
(`timeout`) leaves the Windows kernel running — orphaned kernels burned
CPU for hours before this. The runtime isolates its context path
(`$ContextPath = {"System`"}` while loading) so it can't redefine a
user's existing `Global`` symbols.

**Step 3 note:** Idris closures are now `Clo` data with CPS calling
convention `c[x, k]`. Handing one to a WL function (e.g. a `Select`
predicate) needs an adapter — done in step 3 as `callback[…, c][x]`
(SubValues, not `Function`; see "FFI marshalling").

### FFI marshalling (step 3, implemented 2026-10-24)

**Split (decided with the user): mechanical conversion in WL, type facts
in Idris.** The runtime converts (small, generic, trusted, fast); the
wrapper library is ordinary type-checked Idris that measures and checks.

**Runtime representations** (confirmed with `--dumpcases`, v0.8.0 — the
runtime's converters hard-code them):

| Idris | Runtime value |
|---|---|
| `Bool`, `Ordering` | integer: False 0 / True 1; LT 0, EQ 1, GT 2 |
| `Nat` (and Nat-shaped types) | `Integer` |
| `List`, `Vect` | `Con[0]` / `Con[1, x, xs]` (`_builtin.NIL`/`CONS`) |
| pairs `(a, b)` | `Con[1, a, b]`; `(a, b, c)` nests right |
| `Maybe` | `Con[0]` / `Con[1, x]` |
| `()` | `WolfdrisRT`erased` |
| `Char` | integer code point |

**Pieces:**
- `support/wolfram/runtime.wl`, "Marshalling": `toWL[desc, v]` and
  `fromWL[desc, e]` / `fromWLMaybe`, driven by a **descriptor** of the
  Idris type (`dInteger[]`, `dList[d]`, `dVect[n, d]`, `dPair[d1, d2]`,
  `dFun[d1, d2]`, `dFun2[…]`, …). `fromWL` checks the shape and crashes
  with `ERROR: fromWL: expected List Integer, got {1, 2, x} (Integer
  expected, got x)`; `Int` is range-checked, not wrapped; Doubles are
  normalised through `toDouble` (`Total` can return a bignum or exact `0`).
  Idris functions become `callback[d1, d2, c]` heads (SubValues — applying
  a `Function` would walk the captured environment every call).
- Package **`wolfram`** (`lib/`, installed into `~/.idris2` by
  `scripts/build.sh`; programs use `-p wolfram`):
  `Wolfram.FFI` — opaque `WLExpr` (with `Show`, InputForm), phantom-typed
  `Desc a`, `interface Marshal a where desc : Desc a` (instances: `Integer`,
  `Int`, `Nat`, `Double`, `String`, `Char`, `Bool`, `WLExpr`, `List`,
  `Vect n` (needs `n` at run time), pairs, `a -> b` to WL only),
  `toWL`/`fromWL`/`fromWLMaybe`, `fun2`, `withLengthOf`.
  `Wolfram.List` — `wlSelect`, `wlMap`, `wlSort`, `wlLength`, `wlTotal`.
- A wrapper is a `%foreign "wolfram:Select"` over `WLExpr` plus a few
  lines of Idris; lengths are re-established by `fromList` (measured) or
  `withLengthOf` (checked against the input, so callers don't need `n` at
  run time).
- Codegen: on the `wolfram:` path, `emitForeign` drops erased `Type`
  arguments (foreign defs keep implicits like `{0 a : Type}`). Other
  erased implicits (e.g. `{0 n : Nat}`) are **not** dropped — they'd reach
  WL as `erased` — so foreign signatures avoid them (`prim__dVect` is typed
  as a List descriptor and retyped with `believe_me`; `Desc` is phantom).
- `wlSort` always passes the Idris `compare` (as 1/0/−1): WL's canonical
  order differs (`"a" < "B"`, `-Infinity` after numbers). WL `Sort` with an
  ordering function is stable (checked on 5,000 keys), so it matches
  `Data.List.sort` exactly.
- `wlTotal` only for `Integer` and `Double` (`WLNum`): WL's exact sum
  doesn't wrap, so it would disagree with Idris `sum` on fixed-width ints.
- Deferred (agreed): WL-side handles (`WLVect n a`) that skip conversion
  between chained calls. Add when a program needs it.

**Linear algebra (step 5, first real program, 2026-10-24).**
`Wolfram.LinAlg`: `Matrix m n = Vect m (Vect n Double)`, `wlDet`,
`wlLinearSolve` (`Maybe`), `wlLeastSquares`, `wlEigenvalues`, `wlRoots`
(`Vect (S d) Double -> Maybe (Vect d Complex)`, Nothing if the leading
coefficient is 0). Demo + golden test: `tests/polyfit` (fit a cubic,
roots, cross-check against companion-matrix eigenvalues, linear systems).
A dimension mismatch is a compile error (checked). Patterns it set:
- **`Complex`** is the package's own record (`Wolfram.FFI`; none in base
  or contrib), runtime `Con[1, re, im]` like a pair; `fromWL` also accepts
  real numbers (imaginary part 0).
- **Unevaluated means `Nothing`.** WL signals failure by returning the call
  unevaluated (`LinearSolve` with no solution) or `$Failed`; `fromWLMaybe`'s
  shape check turns any of that into `Nothing` with no per-wrapper code.
- **A `wolfram:` spec can be a WL expression**: it's emitted as the head
  applied to the arguments, e.g.
  `"wolfram:(Module[{x}, x /. NSolve[#.x^Range[0, Length[#] - 1] == 0, x]] &)"`.
  Use it for a little WL glue instead of adding runtime functions.
- Inputs cross as nested lists (`map toList`), outputs are checked with
  `withLengthOf` against something of the promised length, so callers
  never need dimensions at run time.
- Golden output from WL numerics is rounded and sorted (root order, last
  digits aren't specified).

**Symbolic math (step 5, second program, 2026-10-25).** Idris builds
expressions, WL does the calculus. `tests/symbolic` (golden, also the
demo): derivative, antiderivative checked by `Simplify[D[F] - f] == 0`,
`Erf` results inspected by head, Taylor coefficients, `Solve`, a
user-defined `besselJ`, a PNG plot.
- **Representation (decided with the user, after comparing three): a
  generic tree with hidden constructors.** `Wolfram.Symbolic.Expr` =
  `Sym | Var | IntE | RealE | Str | App Expr (List Expr) | Raw WLExpr`,
  exported *without* constructors. Rejected: exporting the constructors
  (anything buildable, `Total[a, b]`, `Sin[1, 2, 3]`), and a closed math
  AST (every result using `Erf`, `Root`, `ConditionalExpression`… would
  come back as an opaque box, and the AST would need growing forever).
  - **Building** only through typed functions: `var`, `Num`/`Neg`/
    `Fractional`/`FromDouble`/`Abs` instances, `^` (**`infixr 10`**:
    `*` is 9 and `+` is 8 in Idris), `sin … tanh`, `exp`, `log`, `sqrt`,
    `pi`, `euler`, `imagI`. These reuse Prelude names (`sin`, `pi` are
    Double-only there); type-directed disambiguation picks ours.
  - **Inspecting** through `view : Expr -> View` (`VAdd`, `VMul`, `VPow`,
    `VFn Func`, `VRat`, …, `VOther name args` for unmodelled heads).
  - **`Wolfram.Symbolic.Unsafe.apply "BesselJ" [n, x]`** for new builders:
    one line per function, opt-in import (it round-trips through WL, so it
    needs no access to the hidden constructors).
  - Results always convert back (`fromWL` never fails for `Expr`); WL
    evaluates and canonicalises as expressions are built.
  - **Variables live in `WolfdrisVar``** so a notebook's own `x = 5`
    can't leak in; `Show` strips the context.
- **`Wolfram.Calculus`**: `wlSimplify`, `wlExpand`, `wlFactor`, `wlD`,
  `wlIntegrate` (Maybe), `wlTaylor` (exactly n+1 coefficients, Maybe),
  `wlSolve` (Maybe; `Just []` = no solutions), `wlSubst`, `wlN`,
  `wlExportPlot` (IO; the first export starts the front end, ~8 s, then
  ~0.2 s each). Failure uses a `{}` / `{result}` glue convention.
- **`SeriesCoefficient` is unsafe**: it gives `0` for `Log[x]`'s
  coefficients at 0, where there's no Taylor series. `wlTaylor` uses
  `Series` and checks for a genuine power series.
- **A foreign returning `Bool` must give 0/1** (`Boole[...]`), not WL's
  `True`/`False` — otherwise "unmatched case" later.
- **Idris doesn't rebuild importers when only a fixity changes**: a stale
  `Unsafe.ttc` brought back the old fixity of `^` (the last import wins).
  `scripts/build.sh` now builds the package from clean.
- Not yet: symbolic paclet exports (a notebook's `Global`x` vs our private
  variables needs its own design); refined types like `Poly` on top.

**WL fact found here — walking a deep list through a variable can turn
quadratic.** `While[…, x = x[[3]]]` over a 30,000-cell `Con` list
usually takes 0.2 s, but sometimes stalls for minutes: after some
kernel-internal event (not identified; it happened at random, and after
a `Pause`), every access to the variable re-evaluates the whole remaining
list. Keeping the list inside `Hold` (`h = Extract[h, {1, 3}, Hold]`)
never stalled (0.25 s per 100,000). `conToList` (also used by `pack` /
`concat`) now walks that way. **Checked in the speed step:**
generated-code-style walks (pattern-substituted argument, `Switch[s[[1]],
…]` tail call, also from a long-lived global) never stalled in 32 runs,
and the slow conformance tests scale linearly, so this is not what makes
them slow. The trigger is still unknown.

### Speed (2026-10-24)

Measured on the three "too slow" conformance tests (scaled-down copies,
`scripts/profile.sh` for call counts):
- **~14 s of every run is the WL kernel starting** (`wolframscript -code 1`
  alone takes that long). Every test pays it.
- **Cost is per-call overhead, linear in the work.** Rough WL 15.1 costs
  per iteration of a CPS loop: bare tail call 1.25 µs, extra lifted call
  1.85, continuation closure 2.8, constructor + `Switch` 3.7. The tests
  make ~15 calls per list cell (bind001), ~120 per pair check (newints),
  ~2,700 per character (json_001's lexer).
- **Fixed: Int wrapping recomputed `2^63` and `2^64` on every call** —
  29 µs per Int64 op vs 1.2 µs with constants computed once per width
  (`wrapS`/`wrapU` in the runtime) plus an in-range fast path.
- **Done: unbounded primitives are inlined** (`inlineOp` in `Emit.idr`):
  Integer `+ - *`, Neg and bitwise ops on all integer types, integer/Char
  comparisons, String `==`, `StrAppend`, `StrLength`. A table call costs
  ~0.9 µs more. Every inlined form computes exactly what the runtime's
  `op` definition does; everything else still goes through the table,
  whose catch-all crashes.
- Result: newints-style work ~2× faster, json ~1.3×, bind ~1.1×; full
  newints estimated ~340 s, json_001 ~530 s; bind001 is borderline (290–330 s against the 300 s limit).
- **Not done (decided with the user): direct style for non-recursive
  leaf functions** (~1.35 µs saved per call, est. 1.3–1.5× more). Do it
  together with readable mode, or when a real program needs the speed:
  it's the same hook (see "Readable WL output").

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
- **No interactive stdin** under `wolframscript -file` (see stdin above).
- **The program runs on Windows, not in WSL.** `currentDir` is a Windows
  path, `prim__os` is `"windows"`, processor count is Windows', WSL
  environment variables aren't visible, and the kernel's stderr is merged
  into stdout.
- **Transcendental functions use WL's implementations**, chez uses C libm;
  they agreed on everything tested, but last-ulp differences are possible.
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
   **Progress 2026-10-22:** all primitives, `Double` with IEEE semantics,
   stdin, IORefs/arrays done; 8/8 differential tests pass.
   **Conformance 2026-10-22:** Idris's own test suite runs against us
   (`scripts/conformance.sh`, [docs/conformance.md](docs/conformance.md)):
   **96/108 pass**; after step 4: **97/108**; after the speed work: **97–98/108** (bind001 is borderline at the time limit). Remaining buckets: speed,
   `Data.Buffer` (mechanical), processes (`system`/`popen`, needs a
   Windows-vs-WSL shell decision first).
3. ✅ **Done 2026-10-24** — **FFI + first wrappers.** Marshalling both
   directions; `Total`, `Map`, `Select`, `Length`, `Sort`. See "FFI
   marshalling".
4. ✅ **Done 2026-10-24 (before step 3)** — **Deep recursion / tail calls.**
   Full CPS + closure conversion; see "CPS + closure conversion".
5. **Grow the wrapper library** as real programs demand it. Mining notes:
   [docs/wrapper-mining.md](docs/wrapper-mining.md).
   **First program 2026-10-24:** typed linear algebra + polynomial
   fitting (`Wolfram.LinAlg`, `tests/polyfit`; see "FFI marshalling").
   **Paclets 2026-10-24:** the same code callable from WL notebooks
   (`Wolfram.Export`, `scripts/paclet.sh`; see Distribution → "Paclets").
   **Symbolic math 2026-10-25:** `Wolfram.Symbolic`, `Wolfram.Calculus`,
   `tests/symbolic` (see "Symbolic math" under FFI marshalling).

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
`support/wolfram/runtime.wl` (see Codegen design). **All `PrimFn`s are
implemented as of step 2** (2026-10-22): integer arithmetic, comparisons,
shifts and bitwise ops; the 8 string ops; `Double` arithmetic, comparisons
and math; all casts. Shifts/bitwise follow chez: `ShiftL` wraps for
bounded types, `ShiftR` is arithmetic, `BAnd`/`BOr`/`BXOr` never wrap.

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

  **As built (step 2), byte-identical to chez in `tests/doubles`:**
  - A Double is a WL machine real, or WL's own `Infinity`, `-Infinity`,
    `Indeterminate` (NaN) — not invented symbols: WL's symbolic arithmetic
    then gets ∞−∞, ∞·0, 1/∞, NaN propagation right for free.
  - Every result goes through `toDouble`; special inputs to math functions
    and all `pow` special cases (C99 rules) are handled explicitly.
  - Comparisons use **exact** values (`SetPrecision[x, Infinity]`): WL's
    `==` and `<` on machine reals have a tolerance (`0.1+0.2 == 0.3` is
    `True` in WL).
  - `pow` computes at 40 digits and rounds.
  - `show` (= chez `number->string`): shortest digits that round-trip;
    plain notation iff 1e-3 ≤ |x| < 1e10, else `d.ddde<n>` (`1e10`,
    `1.2e-4`); subnormals get chez's `|<bits>` suffix (`5e-324|1`);
    specials print `+inf.0`, `-inf.0`, `+nan.0`. Matched chez on 6000
    random bit patterns.
  - Double literals are emitted as `digits`*^exp` (backtick = machine
    precision), from the compiler's own `show`.

  **WL numeric pitfalls found (all confirmed on 15.1.0):**
  - **`N[rational]` is not correctly rounded** — it disagreed with chez's
    `exact->inexact` on 558/3000 random rationals (e.g. `N[10^-23]`). Use
    `fromExact` (exact ties-to-even via `BitLength`/`Round`, built as
    `(m 2^-52) * 2.^e2`) for every rational → Double conversion.
  - **`ImportByteArray[..., "Real64"]` gets every subnormal wrong** (the
    smallest comes back as `0``323.3`, not a machine number). Subnormals
    are built with `SetPrecision[k 2^-1074, MachinePrecision]` instead.
  - **`2.^1024.` returns a finite value** (`1.7976931348622732*^308`), not
    an overflow — hence `pow` at extended precision.
  - `SetPrecision` to subnormals emits `General::munfl` to stdout; wrap
    numeric conversions in `Quiet`.
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

  **Resolved by step 4 (CPS + closure conversion, see above).** Raising
  `$RecursionLimit` alone was unsafe: C stack per limit unit depends on
  code shape (40,000 crashed the kernel for one shape; 20,000 was clean for
  all tried), hence the backstop value 10,000.

  Correction (2026-10-23): hitting the limit does **not** reliably abort
  the whole evaluation — `TerminatedEvaluation["RecursionLimit"]` is often
  returned as a value and evaluation continues (e.g. `{1, deep, 2}` →
  `{1, TerminatedEvaluation[…], 2}`). The runtime's message handler +
  `runMain` now turn it into a clean crash.
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

# build the backend -> build/exec/wolfdris, and install the wolfram package
scripts/build.sh

# compile a program -> build/exec/foo.wl (wrapper sets IDRIS2_DATA)
scripts/wolfdris --cg wolfram Foo.idr -o foo

# run it (Windows wolframscript from WSL)
"/mnt/c/Program Files/Wolfram Research/WolframScript/wolframscript.exe" -file "$(wslpath -w build/exec/foo.wl)"

# differential tests vs chez: all of tests/*/Main.idr, or name some
scripts/test.sh [name...]

# Idris 2's own test suite against us (~10 min; see docs/conformance.md)
scripts/conformance.sh [--only "chez/chez001 base/data_list001"]

# any long run: stop and report if output and CPU stop moving
scripts/watch.sh --stall 300 -- scripts/conformance.sh

# where does a slow program spend its calls? (counts per function / primitive)
scripts/profile.sh build/exec/foo.wl [args...]

# a paclet from a library program (main = Wolfram.Export.library [...])
scripts/paclet.sh Main.idr Name outdir
```

**Long runs: never wait silently.** Run long jobs under
`scripts/watch.sh` (catches *silent* hangs: no output growth, no Linux CPU,
no CPU in Wolfram kernels started by the run) *and* with
`WOLFDRIS_TIMEOUT` (catches busy infinite loops; enforced inside the
kernel). Killing wolframscript from WSL doesn't stop the Windows kernel, so
after a killed run check for orphaned `wolfram` processes — by start time,
so as not to kill a live run.

Test layout: `tests/<name>/Main.idr`, plus an optional `tests/<name>/input`
piped to both programs as stdin; the script compiles with chez and
Wolfdris, strips `\r`, diffs stdout. To add a test, add a directory.
**Golden tests:** if `tests/<name>/expected` exists, chez is skipped (it
can't run `wolfram:` foreigns), the program is compiled with `-p wolfram`,
and its output is diffed against that file. Make them self-checking where
possible (`wlSort xs == sort xs`).
Idris test-writing gotchas: float literals need a `.` (`1.0e9`, not `1e9`);
unannotated literals default to `Integer`; long tuples of overloaded
literals hit the ambiguity-depth limit — use typed lists.

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

### Paclets (implemented 2026-10-24)

```idris
fitEntry : Nat -> List Double -> List Double -> Either String (List Double)
main = library [ fn3 "fit" "fit[d, xs, ys] fits ..." fitEntry, ... ]
```
```bash
scripts/paclet.sh Main.idr PolyFit outdir      # outdir/PolyFit/{PacletInfo.wl, Kernel/PolyFit.wl}
```
```wolfram
PacletDirectoryLoad["outdir/PolyFit"]; Needs["PolyFit`"]; PolyFit`fit[3, xs, ys]
```
- **Exports are registered in `main`** (decided with the user):
  `Wolfram.Export` — `fn1`/`fn2`/`fn3 name usage f`, `library [...]`.
  `Marshal` picks every conversion from the real Idris types, so the
  codegen needs no type knowledge. Rejected: `%export "wolfram:…"` (Idris
  v0.8.0 has it, only JS uses it; the codegen only sees erased code, so it
  would have to read types out of the checker's state).
- **Entry points take plain lists and check them into `Vect`s**
  (`exactLength`, measuring), returning `Either String a`: `Right v` → `v`,
  `Left msg` → `Failure["IdrisError", <|"MessageTemplate" -> msg|>]`.
  Wrong arity, arguments `fromWL` rejects, `idris_crash`, `exit` and stack
  overflow give the same kind of `Failure`; the kernel carries on.
- **Library mode** (`--directive library --directive package=Name`, set by
  `paclet.sh`): the codegen prepends `$library`/`$package`,
  `BeginPackage["Name`"]; EndPackage[]`, ends with `runLibrary[main]`, and
  renames `WolfdrisGen`` → `Name`Gen``, `WolfdrisRT`` → `Name`RT`` (all
  occurrences, strings included — the runtime's own `Begin[...]` and the
  `wolfram:` specs must follow). So several Idris paclets, even built with
  different runtimes, load into one kernel (tested). The runtime then sets
  **no globals** (`$HistoryLength`, `$IterationLimit`, `$RecursionLimit`,
  `$Messages`, `$Output` options); each call runs in `callIdris`, which
  `Block`s the limits and `$Messages = {}` and catches crashes. The
  overflow handler only acts inside calls.
- Exported functions are pure for now (`IO` results: later).
- Test: `tests/paclet` (driver mode in `test.sh`: `paclets` lists the
  names to build, `driver.wl` loads and calls them, output vs `expected`),
  including globals-unchanged and two-paclets-side-by-side checks.

## Conventions

- Wolfram Language unless specified otherwise.
- Append design decisions to this file as they're made. Its value is that it
  accumulates — every session starts cold from what's written here.
- Reference material for later build steps goes in `docs/` and is linked
  from here, to keep this file focused.
