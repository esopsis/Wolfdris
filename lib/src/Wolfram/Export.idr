||| Idris functions callable from Wolfram Language: a paclet.
|||
||| A library program's `main` registers its exports:
|||
|||     main : IO ()
|||     main = library [ fn3 "fit" "fit[d, xs, ys] fits ..." fitEntry ]
|||
||| Built with scripts/paclet.sh, it becomes paclet Name with
||| `Name`fit[d, xs, ys]` defined. Arguments are converted from WL as the
||| Idris types say (`fromWL`); a mismatch, a crash or a `Left` gives
||| `Failure["IdrisError", ...]`, and the caller's kernel carries on.
module Wolfram.Export

import Wolfram.FFI

%default total

||| One exported function.
export
record Export where
  constructor MkExport
  spec : WLExpr

-- exportSpec[name, usage, arity, callbackN[...]], from the argument and
-- result descriptors and the curried function itself
%foreign "wolfram:WolfdrisRT`makeExport"
prim__makeExport : String -> String -> WLExpr -> WLExpr -> f -> WLExpr

-- the same for a function whose result is an IO action, run per call
%foreign "wolfram:WolfdrisRT`makeExportIO"
prim__makeExportIO : String -> String -> WLExpr -> WLExpr -> f -> WLExpr

%foreign "wolfram:WolfdrisRT`defineExports"
prim__defineExports : WLExpr -> PrimIO ()

export
fn1 : (Marshal a, Marshal r) => (name, usage : String) -> (a -> r) -> Export
fn1 n u f = MkExport $ prim__makeExport n u
  (toWL (the (List WLExpr) [descExpr (desc {a})])) (descExpr (desc {a = r})) f

export
fn2 : (Marshal a, Marshal b, Marshal r) => (name, usage : String) -> (a -> b -> r) -> Export
fn2 n u f = MkExport $ prim__makeExport n u
  (toWL (the (List WLExpr) [descExpr (desc {a}), descExpr (desc {a = b})]))
  (descExpr (desc {a = r})) f

export
fn3 : (Marshal a, Marshal b, Marshal c, Marshal r) =>
      (name, usage : String) -> (a -> b -> c -> r) -> Export
fn3 n u f = MkExport $ prim__makeExport n u
  (toWL (the (List WLExpr) [descExpr (desc {a}), descExpr (desc {a = b}), descExpr (desc {a = c})]))
  (descExpr (desc {a = r})) f

||| An export whose result is an `IO` action, run on each call: it can read
||| files, use WL's side effects, print (to the notebook). Crashes still
||| come back as a `Failure`.
export
fnIO1 : (Marshal a, Marshal r) => (name, usage : String) -> (a -> IO r) -> Export
fnIO1 n u f = MkExport $ prim__makeExportIO n u
  (toWL (the (List WLExpr) [descExpr (desc {a})])) (descExpr (desc {a = r})) f

export
fnIO2 : (Marshal a, Marshal b, Marshal r) =>
        (name, usage : String) -> (a -> b -> IO r) -> Export
fnIO2 n u f = MkExport $ prim__makeExportIO n u
  (toWL (the (List WLExpr) [descExpr (desc {a}), descExpr (desc {a = b})]))
  (descExpr (desc {a = r})) f

export
fnIO3 : (Marshal a, Marshal b, Marshal c, Marshal r) =>
        (name, usage : String) -> (a -> b -> c -> IO r) -> Export
fnIO3 n u f = MkExport $ prim__makeExportIO n u
  (toWL (the (List WLExpr) [descExpr (desc {a}), descExpr (desc {a = b}), descExpr (desc {a = c})]))
  (descExpr (desc {a = r})) f

||| Define the exports in the paclet's context. The whole of a library
||| program's `main`.
export
library : List Export -> IO ()
library es = primIO (prim__defineExports (toWL (map spec es)))
