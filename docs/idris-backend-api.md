# Idris 2 v0.8.0 backend API — reference notes

Read from the v0.8.0 source (`~/src/Idris2` in WSL). Paths are relative to
that tree. Facts marked *inferred* were not confirmed by running anything —
`idris2 --dumpcases <file>` dumps the real NamedCExp and will settle them.

## Registering a backend

- `Idris.Driver.mainWithCodegens : List (String, Codegen) -> IO ()`
  (`src/Idris/Driver.idr:269`). The head of the list becomes the default
  codegen; `--cg wolfram` also works.
- `Codegen` (`src/Compiler/Common.idr:40-59`):
  ```idris
  record Codegen where
    constructor MkCG
    compileExpr : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                  (tmpDir : String) -> (outputDir : String) ->
                  ClosedTerm -> (outfile : String) -> Core (Maybe String)
    executeExpr : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                  (tmpDir : String) -> ClosedTerm -> Core ()
    incCompileFile : Maybe (...)   -- Nothing for us
    incExt : Maybe String          -- Nothing for us
  ```
  Smallest example: `codegenNode = MkCG compileExpr executeExpr Nothing Nothing`
  (`src/Compiler/ES/Node.idr:76`).

## Getting the IR

- `getCompileData False Cases tm` (`Compiler.Common`, line 409) →
  `CompileData` with `mainExpr : ClosedCExp` and
  `namedDefs : List (Name, FC, NamedDef)`.
- `forget` (`src/Core/CompileExpr.idr:360`) turns `mainExpr` into
  `NamedCExp`. JS wraps it as a zero-arg function
  `MN "__mainExpression" 0` and calls it; chez emits it inline after all defs.
- The term passed to `compileExpr` is already `unsafePerformIO main`; the
  backend never looks up `Main.main`. main's world is `NmPrimVal WorldVal`.

## IR shapes (`src/Core/CompileExpr.idr`)

```idris
data NamedDef = MkNmFun (args : List Name) NamedCExp
              | MkNmCon (tag : Maybe Int) (arity : Nat) (nt : Maybe Nat)
              | MkNmForeign (ccs : List String) (fargs : List CFType) CFType
              | MkNmError NamedCExp

NmLocal NmRef NmLam NmLet NmApp NmCon NmOp NmExtPrim NmForce NmDelay
NmConCase NmConstCase NmPrimVal NmErased NmCrash
MkNConAlt  : Name -> ConInfo -> (tag : Maybe Int) -> (args : List Name) -> NamedCExp -> NamedConAlt
MkNConstAlt : Constant -> NamedCExp -> NamedConstAlt
```

- `NmApp` args match the callee's arity exactly; over-application is nested.
- `NmCon` is saturated. `tag = Nothing` means match by name.
- Case forms carry `Maybe NamedCExp` as the default branch.
- Bound names are unique (source comment).
- `ConInfo`: `DATACON TYCON NIL CONS ENUM NOTHING JUST RECORD ZERO SUCC UNIT`.

**Primitives** (`src/Core/TT/Primitive.idr`):
- `PrimFn`: `Add Sub Mul Div Mod Neg ShiftL ShiftR BAnd BOr BXOr LT LTE EQ
  GTE GT` (each over a `PrimType`), `StrLength StrHead StrTail StrIndex
  StrCons StrAppend StrReverse StrSubstr` (`StrSubstr` args are
  `[offset, len, str]`), `DoubleExp DoubleLog DoublePow DoubleSin ...
  DoubleFloor DoubleCeiling`, `Cast from to`, `BelieveMe` (value is arg 3),
  `Crash` (message is arg 2). Comparisons return `Int` 0/1.
- `PrimType`: `IntType Int8..64Type IntegerType Bits8..64Type StringType
  CharType DoubleType WorldType`.
- `Constant`: `I I8 I16 I32 I64 BI B8 B16 B32 B64 Str Ch Db PrT WorldVal`.

## Constructor rewrites already applied (`src/Compiler/Opts/Constructor.idr`)

- `NIL`/`CONS`/`NOTHING`/`JUST` → `_builtin.NIL` (tag 0), `_builtin.CONS`
  (tag 1, arity 2), `_builtin.NOTHING` (tag 0), `_builtin.JUST` (tag 1).
  They also appear in `namedDefs` as `MkNmCon`. Chez maps them to native
  Scheme lists.
- **Nat → Integer**: `Z`/`S` become `BI 0` / `+1`; Nat cases become
  `NmConstCase` on Integer.
- **Enums** (all-nullary types) become `B8`/`B16`/`B32` constants.
- Cases on `UNIT` are removed.

## IO and the world

- `IO`, `IORes` are newtypes and erased: an IO action is a one-arg function
  of the world that returns the result directly (no pair).
- Foreign `fargs` include `CFWorld` as a real parameter: `prim__putStr` has
  `fargs = [CFString, CFWorld]`, return `CFIORes CFUnit`.
- **Confirmed** by `--dumpcases` on `main = putStrLn "hello"` — the whole
  program is 14 definitions; `putStrLn` is inlined away:
  ```
  _builtin.NIL = Constructor tag Just 0 arity 0
  _builtin.CONS = Constructor tag Just 1 arity 2
  _builtin.NOTHING = Constructor tag Just 0 arity 0
  _builtin.JUST = Constructor tag Just 1 arity 1
  prim__sub_Integer = [{arg:0}, {arg:1}]: (-Integer [!{arg:0}, !{arg:1}])
  Main.main = [{ext:0}]: (Prelude.IO.prim__putStr ["hello\n", !{ext:0}])
  Prelude.Types.prim__integerToNat = [{arg:0}]: (%case (<=Integer [0, !{arg:0}]) [(%constcase 0 0)] Just !{arg:0})
  Prelude.EqOrd.compare = ... Prelude.EqOrd.== = ... Prelude.EqOrd.< = ...
  Prelude.EqOrd.compareInteger = [{ext:0}, {ext:1}]: (Prelude.EqOrd.compare [!{ext:0}, !{ext:1}])
  Prelude.IO.prim__putStr = Foreign call ["C:idris2_putStr, libidris2_support, idris_support.h", "node:lambda:...", "browser:lambda:..."] [String, %World] -> IORes Unit
  PrimIO.unsafePerformIO = [{arg:1}]: (PrimIO.unsafeCreateWorld [(%lam w (!{arg:1} [!w]))])
  PrimIO.unsafeCreateWorld = [{arg:1}]: (!{arg:1} [%MkWorld])
  ```
  Note the machine-generated local names (`{arg:0}`, `{ext:0}`) — mangling
  must handle them. Some defs (`compare`, `prim__integerToNat`) are always
  included even when unused.

## Foreign functions — the hello-world hurdle

From `libs/prelude/Prelude/IO.idr`:
```idris
%foreign "C:idris2_putStr, libidris2_support, idris_support.h"
         "node:lambda:x=>process.stdout.write(x)"
         "browser:lambda:x=>console.log(x)"
prim__putStr : String -> PrimIO ()

%foreign "C:idris2_getStr, libidris2_support, idris_support.h"
         "node:support:getStr,support_system_file"
prim__getStr : PrimIO String

%foreign "C:putchar,libc 6" "node:lambda:..." "browser:lambda:..."
prim__putChar : Char -> (1 x : %World) -> IORes ()
```

- JS picks the first spec whose prefix is in its list (`node`,
  `javascript`), skips the rest, and **fails compilation** if none matches
  (`src/Compiler/ES/Codegen.idr:486-552`).
- Chez has no `scheme:` spec on these; it uses the `C` spec, via preference
  list `["scheme,chez","scheme","C__collect_safe","C"]` and
  `Compiler.Common.parseCC` (line 477).
- So for Wolfdris every *reachable* `MkNmForeign` needs either a `wolfram:`
  spec or a mapping from its `C:` function name (`idris2_putStr`,
  `putchar`, …) to a WL runtime function.
- `%foreign_impl` (`Compiler.Common.addForeignImpl`, line 248) lets a
  separate library add extra spec strings to existing Prelude prims without
  editing the Prelude — the clean way to attach `wolfram:` specs later.
  Exact pragma syntax not checked.
- `%extern` prims arrive as `NmExtPrim` (IORefs, arrays, `prim__codegen`,
  `prim__os`); JS handles them in `jsPrim` (`ES/Codegen.idr:555-580`).

## Division (chez `support/chez/support.ss:42-53`)

Euclidean: the remainder is always ≥ 0. `Integer`, `Int`, `IntN` use
`blodwen-euclidDiv` (then wrap for bounded types); `BitsN` use `quotient`;
`Mod` is always `blodwen-euclidMod`. WL equivalent, checked against a
transcription of the chez code for all a, b in −9..9 (b ≠ 0):
```wolfram
euclidMod[a_, b_] := Mod[a, Abs[b]]
euclidDiv[a_, b_] := (a - Mod[a, Abs[b]])/b
```
e.g. `-7 div -2 = 4`, `-7 mod -2 = 1`, `-7 div 2 = -4`, `7 div -2 = -3`.

## Name mangling

- JS: `jsMangleName` (`ES/Codegen.idr:106`) — namespaces joined with `_`,
  non-alphanumerics → `x<hex>`.
- Chez: `schName` (`Scheme/Common.idr:41`).
- WL symbols allow only letters, digits and `$` (and contexts via `` ` ``),
  so we need our own escaping.

## JS backend module map (`src/Compiler/ES/`)

`Ast` (JS AST), `Doc` (pretty-printer), `State`, `ToAst` (NamedCExp →
statements), `TailRec` (call-graph TCO, `__tailRec` trampoline), `Codegen`
(mangling, prim ops, FFI, printing; exports `compileToES`, line 789),
`Javascript`/`Node` (thin `Codegen` wrappers).
