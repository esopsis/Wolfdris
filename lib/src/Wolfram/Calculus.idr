||| Typed wrappers around WL's symbolic calculus. Variables are named by
||| string (`wlD f "x"`). Where WL may fail (no closed form, no power
||| series, can't solve), the result is a Maybe: WL leaves such calls
||| unevaluated, and that becomes Nothing.
module Wolfram.Calculus

import Data.Vect
import Wolfram.FFI
import Wolfram.Symbolic

%default total

-- Glue in the specs returns {} for failure and {result} for success, so
-- a list conversion tells them apart.

%foreign "wolfram:Simplify"
prim__simplify : WLExpr -> WLExpr

%foreign "wolfram:Expand"
prim__expand : WLExpr -> WLExpr

%foreign "wolfram:Factor"
prim__factor : WLExpr -> WLExpr

%foreign "wolfram:D"
prim__d : WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:(With[{r = Integrate[#1, #2]}, If[FreeQ[r, Integrate], {r}, {}]] &)"
prim__integrate : WLExpr -> WLExpr -> WLExpr

-- A genuine power series only: no negative or fractional powers and no
-- coefficients still involving x (e.g. Log[x] at 0). SeriesCoefficient
-- can't be used here: it gives 0 for Log[x]'s coefficients at 0.
%foreign "wolfram:(Module[{s = Series[#1, {#2, #3, #4}]}, Which[Head[s] =!= SeriesData, If[FreeQ[s, #2], {PadRight[{s}, #4 + 1]}, {}], s[[4]] >= 0 && s[[6]] == 1 && FreeQ[s[[3]], #2], {PadRight[Join[ConstantArray[0, s[[4]]], s[[3]]], #4 + 1]}, True, {}]] &)"
prim__taylor : WLExpr -> WLExpr -> WLExpr -> Integer -> WLExpr

%foreign "wolfram:(With[{r = Solve[#1 == #2, #3]}, If[Head[r] === Solve, {}, {#3 /. r}]] &)"
prim__solve : WLExpr -> WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:(#1 /. #2 -> #3 &)"
prim__subst : WLExpr -> WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:(With[{r = N[#]}, If[Head[r] === Real, {r}, {}]] &)"
prim__n : WLExpr -> WLExpr

-- Bool results must be 0/1 at run time
%foreign "wolfram:(Boole[Quiet[Check[Export[#1, Plot[#2, {#3, #4, #5}]], $Failed]] =!= $Failed] &)"
prim__exportPlot : String -> WLExpr -> WLExpr -> Double -> Double -> PrimIO Bool

-- The {} / {result} convention
maybeOne : Marshal a => WLExpr -> Maybe a
maybeOne r = case the (List a) (fromWL r) of
  [x] => Just x
  _ => Nothing

export
simplify : Expr -> Expr
simplify e = fromWL (prim__simplify (toWL e))

export
expand : Expr -> Expr
expand e = fromWL (prim__expand (toWL e))

export
factor : Expr -> Expr
factor e = fromWL (prim__factor (toWL e))

||| The derivative with respect to a variable (`D`).
export
wlD : Expr -> (x : String) -> Expr
wlD e x = fromWL (prim__d (toWL e) (toWL (var x)))

||| An antiderivative (`Integrate`), or Nothing if WL finds no closed form.
export
integrate : Expr -> (x : String) -> Maybe Expr
integrate e x = maybeOne (prim__integrate (toWL e) (toWL (var x)))

||| The coefficients of the Taylor polynomial of order n around `at`
||| (`Series`): exactly n + 1 of them, lowest power first. Nothing if the
||| expression has no power series there.
export
taylor : (n : Nat) -> Expr -> (x : String) -> (at : Expr) -> Maybe (Vect (S n) Expr)
taylor n e x a
    = map check (maybeOne (prim__taylor (toWL e) (toWL (var x)) (toWL a) (natToInteger n)))
  where
    check : List Expr -> Vect (S n) Expr
    check cs = case exactLength (S n) (fromList cs) of
      Just v => v
      Nothing => assert_total $ idris_crash "taylor: wrong number of coefficients"

||| The solutions of lhs == rhs for a variable (`Solve`), or Nothing if WL
||| can't solve it. `Just []` means there are no solutions.
export
solve : (lhs, rhs : Expr) -> (x : String) -> Maybe (List Expr)
solve l r x = maybeOne (prim__solve (toWL l) (toWL r) (toWL (var x)))

||| Replace a variable by an expression.
export
subst : Expr -> (x : String) -> Expr -> Expr
subst e x v = fromWL (prim__subst (toWL e) (toWL (var x)) (toWL v))

||| The numeric value (`N`), or Nothing unless it is a real number.
export
wlN : Expr -> Maybe Double
wlN e = maybeOne (prim__n (toWL e))

||| Plot the expression for x from lo to hi into a file (`Export`; the
||| format follows the extension, e.g. .png, .pdf). False if WL couldn't.
||| The first export in a session starts WL's front end (several seconds).
export
exportPlot : HasIO io => (file : String) -> Expr -> (x : String) -> (lo, hi : Double) -> io Bool
exportPlot file e x lo hi = primIO (prim__exportPlot file (toWL e) (toWL (var x)) lo hi)
