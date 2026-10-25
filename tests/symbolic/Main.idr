module Main

import Data.List
import Data.Vect
import Wolfram.Calculus
import Wolfram.Symbolic
import Wolfram.Symbolic.Unsafe

-- Symbolic math: Idris builds expressions, WL does the calculus.
-- Golden test (wolfram only): see `expected`.

x : Expr
x = var "x"

f : Expr
f = x ^ 2 * sin x

-- A WL function the library doesn't have, defined in one line. Only this
-- line vouches for the name and arity; every use is typed.
besselJ : Expr -> Expr -> Expr
besselJ n z = apply "BesselJ" [n, z]

-- Doesn't compile: Expr's constructors aren't exported, and sin takes
-- exactly one argument.
-- bad1 : Expr
-- bad1 = App (Sym "Total") [x, x]
-- bad2 : Expr
-- bad2 = sin x x

-- A program's own foreign call (Bools are 0/1 at run time)
%foreign "wolfram:(Boole[FileExistsQ[#]] &)"
fileExists : String -> Bool

||| The heads in an expression, outermost first, through the typed view.
covering
heads : Expr -> List String
heads e = case view e of
  VAdd ts => "Plus" :: concatMap heads ts
  VMul ts => "Times" :: concatMap heads ts
  VPow a b => "Power" :: heads a ++ heads b
  VFn g ts => show g :: concatMap heads ts
  VOther h ts => h :: concatMap heads ts
  _ => []

||| Six decimals (for positive numbers): WL's last digits aren't specified.
fixed6 : Double -> String
fixed6 d = let n = cast {to = Integer} (floor (d * 1000000.0 + 0.5))
               frac = show (n `mod` 1000000) in
           show (n `div` 1000000) ++ "." ++ pack (replicate (minus 6 (length frac)) '0') ++ frac

covering
main : IO ()
main = do
  putStrLn $ "f = " ++ show f
  putStrLn $ "f' = " ++ show (wlD f "x")
  case wlIntegrate f "x" of
    Nothing => putStrLn "no antiderivative"
    Just big => do
      putStrLn $ "integral of f = " ++ show big
      putStrLn $ "derivative of the integral is f: " ++ show (wlSimplify (wlD big "x" - f) == 0)
  let gauss = wlIntegrate (exp (negate (x ^ 2))) "x"
  putStrLn $ "integral of e^-x^2 = " ++ show gauss
  putStrLn $ "its heads: " ++ show (maybe [] heads gauss)
  putStrLn $ "integral of sin x / x^x = " ++ show (wlIntegrate (sin x / x ^ x) "x")
  putStrLn $ "Taylor e^x, order 4: " ++ show (map toList (wlTaylor 4 (exp x) "x" 0))
  putStrLn $ "Taylor log x at 0: " ++ show (map toList (wlTaylor 2 (log x) "x" 0))
  putStrLn $ "Taylor 1/(1-x), order 3: " ++ show (map toList (wlTaylor 3 (1 / (1 - x)) "x" 0))
  putStrLn $ "solve x^2 == 2: " ++ show (wlSolve (x ^ 2) 2 "x")
  putStrLn $ "solve x^2 == -1: " ++ show (wlSolve (x ^ 2) (-1) "x")
  putStrLn $ "solve sin x == x^3 + e^x: " ++ show (wlSolve (sin x) (x ^ 3 + exp x) "x")
  case view (wlExpand ((x + 1) ^ 5)) of
    VAdd ts => putStrLn $ "(x + 1)^5 expands to " ++ show (length ts) ++ " terms"
    _ => putStrLn "not a sum"
  putStrLn $ "factor x^2 - 1: " ++ show (wlFactor (x ^ 2 - 1))
  putStrLn $ "f at pi/2: " ++ show (wlSubst f "x" (pi / 2))
  putStrLn $ "numerically: " ++ show (map fixed6 (wlN (wlSubst f "x" (pi / 2))))
  putStrLn $ "BesselJ[0, 1] = " ++ show (map fixed6 (wlN (besselJ 0 1)))
  putStrLn $ "a symbol isn't a number: " ++ show (wlN x)
  ok <- wlExportPlot "build/plot.png" f "x" (-3.0) 3.0
  putStrLn $ "plot exported: " ++ show ok ++ ", file exists: " ++ show (fileExists "build/plot.png")
