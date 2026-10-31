module Main

import Data.List
import Data.Vect
import Wolfram.FFI
import Wolfram.LinAlg

-- Fit a polynomial to sampled data, find its roots, solve linear systems:
-- Idris keeps the dimensions straight, WL does the numerics.
-- Golden test (wolfram only): see `expected`.

||| 1, x, x^2, ..., x^d
powers : (d : Nat) -> Double -> Vect (S d) Double
powers Z _ = [1.0]
powers (S k) x = 1.0 :: map (* x) (powers k x)

||| Least-squares fit of a degree-d polynomial to the points (x_i, y_i):
||| d + 1 coefficients, lowest degree first.
fit : (d : Nat) -> Vect (S m) Double -> Vect (S m) Double -> Vect (S d) Double
fit d xs ys = leastSquares (map (powers d) xs) ys

||| A matrix whose eigenvalues are the roots of the cubic c0 + c1 x + c2 x^2 + c3 x^3.
companion : Vect 4 Double -> Matrix 3 3
companion [c0, c1, c2, c3] =
  [ [0.0, 0.0, -c0 / c3]
  , [1.0, 0.0, -c1 / c3]
  , [0.0, 1.0, -c2 / c3] ]

mulMV : Matrix m n -> Vect n Double -> Vect m Double
mulMV a x = map (\r => sum (zipWith (*) r x)) a

-- WL's last digits and root order aren't specified: compare rounded and sorted.
approx : Double -> Double
approx x = floor (x * 1000.0 + 0.5) / 1000.0

approxC : Complex -> Complex
approxC (MkComplex a b) = MkComplex (approx a) (approx b)

sorted : Vect n Complex -> List Complex
sorted = sortBy (\z, w => compare (re z, im z) (re w, im w)) . map approxC . toList

||| Roots at -1.5, 1 and 2: 3 - 2.5x - 1.5x^2 + x^3.
cubic : Double -> Double
cubic x = (x + 1.5) * (x - 1.0) * (x - 2.0)

xs : Vect 10 Double
xs = [-2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5]

-- the samples, with a small deterministic wobble
ys : Vect 10 Double
ys = map (\x => cubic x + 0.00001 * sin (7.0 * x)) xs

a : Matrix 3 3
a = [[2.0, 1.0, -1.0], [-3.0, -1.0, 2.0], [-2.0, 1.0, 2.0]]

b : Vect 3 Double
b = [8.0, -11.0, -3.0]

-- Doesn't compile: a 3x3 system needs a right-hand side of length 3.
-- bad : Maybe (Vect 3 Double)
-- bad = linearSolve a [1.0, 2.0]

main : IO ()
main = do
  let cs = fit 3 xs ys
  putStrLn $ "fit coefficients: " ++ show (map approx cs)
  case roots cs of
    Nothing => putStrLn "the fit isn't a cubic"
    Just rs => do
      putStrLn $ "roots of the fit: " ++ show (sorted rs)
      putStrLn $ "companion eigenvalues agree: "
        ++ show (sorted (eigenvalues (companion cs)) == sorted rs)
  let sol = linearSolve a b
  putStrLn $ "solution: " ++ show (map (map approx) sol)
  putStrLn $ "residual small: "
    ++ show (maybe False (\x => all (\r => abs r < 1.0e-9) (zipWith (-) (mulMV a x) b)) sol)
  putStrLn $ "det: " ++ show (approx (det a))
  let s = the (Matrix 2 2) [[1.0, 2.0], [2.0, 4.0]]
  putStrLn $ "singular system: " ++ show (linearSolve s [1.0, 1.0])
  putStrLn $ "det: " ++ show (approx (det s))
  putStrLn $ "roots of x^2 + 1: " ++ show (map sorted (roots [1.0, 0.0, 1.0]))
  putStrLn $ "degree drops: " ++ show (map sorted (roots [1.0, 1.0, 0.0]))
  putStrLn $ "rotation eigenvalues: " ++ show (sorted (eigenvalues [[0.0, -1.0], [1.0, 0.0]]))
