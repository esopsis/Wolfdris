# Wrapper mining

Notes for step 5 (growing the wrapper library). Linked from `CLAUDE.md`.

## WL documentation mining

Useful for drafting wrapper types — mine what a function actually accepts and
returns, then write the Idris type by hand. Verified working.

`WolframLanguageData[name, "DocumentationExampleInputs"]` returns example
inputs grouped by doc section as `RawBoxes[Cell[BoxData[...]]]`.

```wolfram
held = Replace[cell,
  RawBoxes[Cell[BoxData[b_], ___]] :> ToExpression[b, StandardForm, HoldComplete]];
calls = Cases[held, HoldPattern[f[zz___]] :> HoldComplete[f[zz]], {0, Infinity}];
```

Then `Replace[call, HoldComplete[f[zz___]] :> <|"in" -> typeOf /@ {zz},
"out" -> typeOf[f[zz]]|>]` to evaluate and record.

On `Total`: 29 observations, ~20 clean. The rank-reduction behavior
(`Array[Int,{3,3}] -> Array[Int,{3}]`) is directly readable from the data.

**Gotchas, all hit during the prototype:**

- `RawBoxes` is `HoldAllComplete`, which shields patterns in a *downvalue*
  definition. Use `Replace` on the expression, not `toHeld[pattern] := ...`.
- `HoldPattern[f[...]]` with `f` a local variable does **not** substitute.
  Inject with `With[{f = Symbol[name]}, ...]`.
- A `RuleDelayed` RHS replaced *inside* `HoldComplete` is inserted
  unevaluated, so side effects never fire. Use `Cases` to pull matches out
  where they can evaluate.
- Examples share a global namespace and leak assignments between sections.
  Evaluate each group in a fresh context — skipping this caused most of the
  prototype's noise.
- Wrap everything in `TimeConstrained`.

Mined signatures are **systematically too narrow** — they reflect whatever the
doc examples happened to cover. Treat as drafts for human review, never as
authoritative.

## Also worth harvesting: compiler type environment

`Compile\`TypeEnvironment["Current"]` is a real object and `Compile\`TypeJoin`
exists. The compiler must have curated signatures for builtins since
`FunctionCompile` needs them — potentially useful ground truth for wrapper
types. Caveat: these are signatures over machine types (`Integer64`,
`Real64`, packed arrays), so they cover the numeric subset, not general WL.

**Status: not harvested.** The accessor API wasn't found on a first attempt;
`tenv["FunctionTypeLookup"]` and `tenv["getAbstractTypes"]` are both wrong.
Try `Names["Compile\`*"]` and reading the paclet source.
