||| Typed wrappers around WL's differential equation solvers: `NDSolve`
||| (numeric) and `DSolve` (exact), for systems y' = f(t, y) of n
||| first-order equations. The dimension is in the types, so a right-hand
||| side of the wrong size doesn't compile.
|||
||| The right-hand side is either an Idris function (any Idris code; WL
||| calls it back at every step) or a symbolic system built with
||| `Wolfram.Symbolic` (WL works with it directly, and can solve it exactly).
module Wolfram.ODE

import Data.Vect
import Wolfram.FFI
import Wolfram.Symbolic

%default total

||| A numerical solution of an n-dimensional system. It stays in WL (as the
||| interpolating functions `NDSolve` returns); read it with `sample` and
||| `table`.
export
data Solution : Nat -> Type where
  -- y0 is kept to check WL's results against: they must have length n
  MkSolution : (y0 : Vect n Double) -> (t0, tEnd, t1 : Double) -> WLExpr -> Solution n

%foreign "wolfram:WolfdrisRT`odeSolve"
prim__odeSolve : WLExpr -> WLExpr -> Double -> Double -> WLExpr

%foreign "wolfram:WolfdrisRT`odeSolveSym"
prim__odeSolveSym : WLExpr -> WLExpr -> WLExpr -> WLExpr -> Double -> Double -> WLExpr

%foreign "wolfram:WolfdrisRT`odeDSolve"
prim__dsolve : WLExpr -> WLExpr -> WLExpr -> WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:WolfdrisRT`odeAt"
prim__at : WLExpr -> Double -> WLExpr

%foreign "wolfram:WolfdrisRT`odeTable"
prim__table : WLExpr -> Double -> Double -> Integer -> WLExpr

-- Bool results must be 0/1 at run time
%foreign "wolfram:WolfdrisRT`odeExportPlot"
prim__exportPlot : String -> WLExpr -> Double -> Double -> WLExpr -> PrimIO Bool

-- The runtime gives {handle, tEnd}, or a Failure (a Left) with WL's message.
mkSolution : Vect n Double -> (t0, t1 : Double) -> WLExpr -> Either String (Solution n)
mkSolution y0 t0 t1 r
    = map (\(h, tEnd) => MkSolution y0 t0 tEnd t1 h) (fromWL {a = Either String (WLExpr, Double)} r)

||| Solve y' = rhs t y from t0 to t1 with y(t0) = y0 (`NDSolve`). A Left
||| has WL's reason (e.g. the right-hand side gave NaN). If the solver had
||| to stop early (a blow-up), the solution covers the part it solved; see
||| `stopReason`. t1 may be before t0.
export
nDSolve : (rhs : Double -> Vect n Double -> Vect n Double) -> (y0 : Vect n Double) ->
           (t0, t1 : Double) -> Either String (Solution n)
nDSolve rhs y0 t0 t1 = mkSolution y0 t0 t1 (prim__odeSolve (fun2 f) (toWL (toList y0)) t0 t1)
  where
    f : Double -> List Double -> List Double
    f t ys = toList (rhs t (withLengthOf "nDSolve" y0 ys))

||| Like `nDSolve`, for a system given symbolically: variable `vars[i]` has
||| derivative `rhs[i]` with respect to the time variable t, e.g.
||| `nDSolveSym "t" ["x", "v"] [var "v", - sin (var "x")] [1.0, 0.0] 0.0 20.0`.
export
nDSolveSym : (t : String) -> (vars : Vect n String) -> (rhs : Vect n Expr) ->
              (y0 : Vect n Double) -> (t0, t1 : Double) -> Either String (Solution n)
nDSolveSym t vars rhs y0 t0 t1
    = mkSolution y0 t0 t1
        (prim__odeSolveSym (toWL (var t)) (toWL (toList (map var vars))) (toWL (toList rhs))
           (toWL (toList y0)) t0 t1)

||| The exact solution of a symbolic system with the variables equal to y0
||| at t = t0 (`DSolve`): each variable as an expression in t. Nothing if
||| WL finds no closed form, or more than one solution.
export
dSolve : (t : String) -> (vars : Vect n String) -> (rhs : Vect n Expr) ->
         (y0 : Vect n Expr) -> (t0 : Expr) -> Maybe (Vect n Expr)
dSolve t vars rhs y0 t0
    = case the (List (List Expr))
             (fromWL (prim__dsolve (toWL (var t)) (toWL (toList (map var vars)))
                        (toWL (toList rhs)) (toWL (toList y0)) (toWL t0))) of
        [ys] => Just (withLengthOf "dSolve" vars ys)
        _ => Nothing

||| The time span solved, (t0, tEnd), in the direction of integration.
||| tEnd is t1 unless the solver stopped early.
export
domain : Solution n -> (Double, Double)
domain (MkSolution _ t0 tEnd _ _) = (t0, tEnd)

||| Why the solution stops short of t1, if it does.
export
stopReason : Solution n -> Maybe String
stopReason (MkSolution _ _ tEnd t1 _)
    = if tEnd == t1
         then Nothing
         else Just ("stopped at t = " ++ show tEnd ++ " (singularity or stiff system suspected)")

||| The state at time t, or Nothing outside the solved span (WL would
||| extrapolate, often wildly).
export
sample : Solution n -> Double -> Maybe (Vect n Double)
sample (MkSolution y0 t0 tEnd _ h) t
    = if min t0 tEnd <= t && t <= max t0 tEnd
         then Just (withLengthOf "sample" y0 (fromWL (prim__at h t)))
         else Nothing

||| steps + 1 evenly spaced samples over the solved span, from t0 to tEnd.
export
table : Solution n -> (steps : Nat) -> List (Double, Vect n Double)
table (MkSolution y0 t0 tEnd _ h) k
    = map (\(t, ys) => (t, withLengthOf "table" y0 ys))
          (fromWL {a = List (Double, List Double)} (prim__table h t0 tEnd (natToInteger k)))

||| Plot every component against t over the solved span into a file
||| (`Export`; the format follows the extension), one legend label per
||| component. False if WL couldn't. The first export in a session starts
||| WL's front end (several seconds).
export
exportSolutionPlot : HasIO io => (file : String) -> Solution n -> (labels : Vect n String) -> io Bool
exportSolutionPlot file (MkSolution _ t0 tEnd _ h) labels
    = primIO (prim__exportPlot file h (min t0 tEnd) (max t0 tEnd) (toWL (toList labels)))
