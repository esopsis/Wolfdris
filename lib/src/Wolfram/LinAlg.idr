||| Typed wrappers around Wolfram Language linear algebra and root finding.
|||
||| Dimensions are in the types, so a shape mismatch doesn't compile, and
||| what WL returns is checked against what the types promise.
module Wolfram.LinAlg

import Data.Vect
import Wolfram.FFI

%default total

||| An m × n matrix of Doubles, as a vector of rows.
public export
Matrix : Nat -> Nat -> Type
Matrix m n = Vect m (Vect n Double)

-- Matrices go to WL as nested lists, so callers don't need the dimensions
-- at run time.
rows : Matrix m n -> List (List Double)
rows = toList . map toList

%foreign "wolfram:Det"
prim__det : WLExpr -> WLExpr

%foreign "wolfram:LinearSolve"
prim__linearSolve : WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:LeastSquares"
prim__leastSquares : WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:Eigenvalues"
prim__eigenvalues : WLExpr -> WLExpr

-- The roots, with multiplicity, of the polynomial with these coefficients
-- (lowest degree first). A spec can hold a WL expression: it is emitted as
-- the head applied to the arguments.
%foreign "wolfram:(Module[{x}, x /. NSolve[#.x^Range[0, Length[#] - 1] == 0, x]] &)"
prim__roots : WLExpr -> WLExpr

||| The determinant (`Det`).
export
wlDet : Matrix n n -> Double
wlDet a = fromWL (prim__det (toWL (rows a)))

||| An x with a x = b (`LinearSolve`), or Nothing if there is none. For a
||| singular but consistent system, WL picks one of the solutions.
export
wlLinearSolve : Matrix n n -> Vect n Double -> Maybe (Vect n Double)
wlLinearSolve a b
    = map (withLengthOf "wlLinearSolve" b)
          (fromWLMaybe (prim__linearSolve (toWL (rows a)) (toWL (toList b))))

||| The x minimising |a x - b| (`LeastSquares`). At least one row, so the
||| number of columns can be checked.
export
wlLeastSquares : Matrix (S m) n -> Vect (S m) Double -> Vect n Double
wlLeastSquares a b
    = withLengthOf "wlLeastSquares" (head a)
        (fromWL (prim__leastSquares (toWL (rows a)) (toWL (toList b))))

||| The n eigenvalues, with multiplicity (`Eigenvalues`: largest absolute
||| value first).
export
wlEigenvalues : Matrix n n -> Vect n Complex
wlEigenvalues a = withLengthOf "wlEigenvalues" a (fromWL (prim__eigenvalues (toWL (rows a))))

||| The d roots, with multiplicity, of the degree-d polynomial with these
||| coefficients (lowest degree first, `NSolve`), or Nothing if the leading
||| coefficient is 0 (then the degree is lower than d).
export
wlRoots : Vect (S d) Double -> Maybe (Vect d Complex)
wlRoots cs
    = if last cs == 0
         then Nothing
         else Just (withLengthOf "wlRoots" (init cs) (fromWL (prim__roots (toWL (toList cs)))))
