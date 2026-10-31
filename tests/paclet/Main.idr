module Main

import Data.List
import Data.Vect
import Wolfram.Export
import Wolfram.FFI
import Wolfram.LinAlg

-- A paclet: these functions are callable from WL as PolyFit`fit[...] etc.
-- (scripts/paclet.sh builds it; driver.wl calls it). Plain lists come in
-- from WL; each entry point checks them into the Vect types that the
-- typed code needs, and says what's wrong when they don't fit.

powers : (d : Nat) -> Double -> Vect (S d) Double
powers Z _ = [1.0]
powers (S k) x = 1.0 :: map (* x) (powers k x)

||| fit[d, xs, ys]: least-squares fit of a degree-d polynomial.
fitEntry : Nat -> List Double -> List Double -> Either String (List Double)
fitEntry _ [] _ = Left "fit needs at least one point"
fitEntry d (x :: xs) ys
    = case exactLength (S (length xs)) (fromList ys) of
        Nothing => Left "xs and ys differ in length"
        Just vy => Right (toList (leastSquares (map (powers d) (fromList (x :: xs))) vy))

||| roots[coeffs]: the roots of a polynomial, lowest-degree coefficient first.
rootsEntry : List Double -> Either String (List Complex)
rootsEntry [] = Left "roots needs at least one coefficient"
rootsEntry (c :: cs)
    = case roots (fromList (c :: cs)) of
        Nothing => Left "the leading coefficient is 0"
        Just rs => Right (toList rs)

||| solve[a, b]: x with a.x == b, for a square matrix a.
solveEntry : List (List Double) -> List Double -> Either String (List Double)
solveEntry rows b
    = case traverse (\r => exactLength (length b) (fromList r)) rows of
        Nothing => Left "every row of the matrix must have as many entries as b"
        Just rs => case exactLength (length b) (fromList rs) of
          Nothing => Left "the matrix must have as many rows as b"
          Just a => case linearSolve a (fromList b) of
            Nothing => Left "no solution"
            Just x => Right (toList x)

||| sumTo[n]: deep (non-tail) recursion inside a call.
sumTo : Integer -> Integer
sumTo n = sum [1 .. n]

||| boom[n]: an Idris crash, which the caller sees as a Failure.
boom : Integer -> Integer
boom n = if n > 0 then assert_total (idris_crash "boom!") else n

greet : String -> String
greet s = "Hello, " ++ s ++ "!"

main : IO ()
main = library
  [ fn3 "fit" "fit[d, xs, ys] fits a degree-d polynomial to the points (xs, ys); coefficients lowest degree first." fitEntry
  , fn1 "roots" "roots[coeffs] gives the roots of the polynomial with these coefficients, lowest degree first." rootsEntry
  , fn2 "solve" "solve[a, b] gives x with a.x == b for a square matrix a." solveEntry
  , fn1 "sumTo" "sumTo[n] gives 1 + 2 + ... + n." sumTo
  , fn1 "boom" "boom[n] crashes for n > 0." boom
  , fn1 "greet" "greet[name] greets." greet ]
