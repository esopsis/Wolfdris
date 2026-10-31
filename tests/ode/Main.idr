module Main

import Data.List
import Data.String
import Data.Vect
import Wolfram.Calculus
import Wolfram.Symbolic
import Wolfram.ODE

-- Differential equations: Idris states the system (as an Idris function
-- or symbolically), WL's NDSolve and DSolve solve it. The dimension is in
-- the types; each result is checked against what physics says it must be.
-- Golden test (wolfram only): see `expected`.

-- A program's own foreign call (Bools are 0/1 at run time)
%foreign "wolfram:(Boole[FileExistsQ[#]] &)"
fileExists : String -> Bool

||| Four decimals, signed: WL's last digits aren't specified.
fixed : Double -> String
fixed d = let n = cast {to = Integer} (floor (abs d * 10000.0 + 0.5))
              frac = show (n `mod` 10000) in
          (if d < 0.0 && n /= 0 then "-" else "") ++ show (n `div` 10000) ++ "."
            ++ pack (replicate (minus 4 (length frac)) '0') ++ frac

showV : Vect n Double -> String
showV v = "[" ++ joinBy ", " (map fixed (toList v)) ++ "]"

showM : Maybe (Vect n Double) -> String
showM = maybe "Nothing" showV

maxBy : (a -> Double) -> List a -> Double
maxBy f = foldl (\m, x => max m (f x)) 0.0

-- Pendulum: angle and angular velocity.
pendulum : Double -> Vect 2 Double -> Vect 2 Double
pendulum _ [th, om] = [om, - sin th]

energy : Vect 2 Double -> Double
energy [th, om] = om * om / 2.0 - cos th

-- Doesn't compile: the right-hand side of a 2-dimensional system gives 2
-- components.
-- bad : Double -> Vect 2 Double -> Vect 2 Double
-- bad _ [th, om] = [om]

-- Predator and prey; x - ln x + y - ln y stays constant along a solution.
lotkaVolterra : Double -> Vect 2 Double -> Vect 2 Double
lotkaVolterra _ [x, y] = [x * (1.0 - y), - y * (1.0 - x)]

conserved : Vect 2 Double -> Double
conserved [x, y] = x - log x + y - log y

-- Three equal masses (G = 1) in the plane: positions, then velocities.
accel : (Double, Double) -> (Double, Double) -> (Double, Double)
accel (px, py) (qx, qy)
    = let dx = qx - px
          dy = qy - py
          r3 = pow (dx * dx + dy * dy) 1.5 in
      (dx / r3, dy / r3)

plus : (Double, Double) -> (Double, Double) -> (Double, Double)
plus (a, b) (c, d) = (a + c, b + d)

threeBody : Double -> Vect 12 Double -> Vect 12 Double
threeBody _ [x1, y1, x2, y2, x3, y3, u1, v1, u2, v2, u3, v3]
    = let p1 = (x1, y1)
          p2 = (x2, y2)
          p3 = (x3, y3)
          (a1x, a1y) = accel p1 p2 `plus` accel p1 p3
          (a2x, a2y) = accel p2 p1 `plus` accel p2 p3
          (a3x, a3y) = accel p3 p1 `plus` accel p3 p2 in
      [u1, v1, u2, v2, u3, v3, a1x, a1y, a2x, a2y, a3x, a3y]

-- The figure-eight orbit (Chenciner and Montgomery), period about 6.3259.
figureEight : Vect 12 Double
figureEight = [ 0.97000436, -0.24308753, -0.97000436, 0.24308753, 0.0, 0.0
              , 0.466203685, 0.43236573, 0.466203685, 0.43236573, -0.93240737, -0.86473146 ]

distance : Vect n Double -> Vect n Double -> Double
distance a b = sqrt (sum (zipWith (\x, y => (x - y) * (x - y)) a b))

report : String -> Either String (Solution n) -> (Solution n -> IO ()) -> IO ()
report what (Left err) _ = putStrLn $ what ++ ": failed: " ++ err
report what (Right s) k = k s

covering
main : IO ()
main = do
  -- 1. pendulum, right-hand side in Idris
  report "pendulum" (odeSolve pendulum [1.0, 0.0] 0.0 20.0) $ \s => do
    putStrLn $ "pendulum domain: " ++ show (domain s) ++ ", stopped early: " ++ show (stopReason s)
    putStrLn $ "pendulum at t = 20: " ++ showM (sample s 20.0)
    let e0 = energy [1.0, 0.0]
    putStrLn $ "energy drift below 1e-5: "
      ++ show (maxBy (\(_, y) => abs (energy y - e0)) (table s 200) < 1.0e-5)
    putStrLn $ "pendulum table: " ++ joinBy "; " (map (\(t, y) => fixed t ++ " " ++ showV y) (table s 4))
    -- 2. the same system, symbolically
    report "symbolic pendulum"
      (odeSolveSym "t" ["th", "om"] [var "om", - sin (var "th")] [1.0, 0.0] 0.0 20.0) $ \s' =>
      putStrLn $ "symbolic agrees within 1e-6: "
        ++ show (all (\t => maybe False id [| (\a, b => distance a b < 1.0e-6) (sample s t) (sample s' t) |])
                     (the (List Double) [0.0, 5.0, 12.5, 20.0]))
    ok <- wlExportSolutionPlot "build/pendulum.png" s ["angle", "angular velocity"]
    putStrLn $ "plot exported: " ++ show ok ++ ", file exists: " ++ show (fileExists "build/pendulum.png")

  -- 3. predator and prey
  report "lotka-volterra" (odeSolve lotkaVolterra [2.0, 1.0] 0.0 100.0) $ \s => do
    let c0 = conserved [2.0, 1.0]
    putStrLn $ "conserved quantity drift below 1e-4: "
      ++ show (maxBy (\(_, y) => abs (conserved y - c0)) (table s 500) < 1.0e-4)

  -- 4. harmonic oscillator, exactly and numerically
  case dsolve "t" ["x", "v"] [var "v", - var "x"] [1, 0] 0 of
    Nothing => putStrLn "dsolve: no solution"
    Just exact => do
      putStrLn $ "exact: " ++ show exact
      report "oscillator" (odeSolve (\_, [x, v] => [v, - x]) [1.0, 0.0] 0.0 10.0) $ \s =>
        putStrLn $ "numerical agrees with exact: "
          ++ show (all (\t => case (sample s t, traverse (\e => wlN (wlSubst e "t" (fromDouble t))) exact) of
                                (Just a, Just b) => distance a b < 1.0e-5
                                _ => False)
                       (the (List Double) [0.0, 1.5, 3.0, 7.25, 10.0]))

  -- 5. y' = y^2 blows up at t = 1: the solution stops there
  report "blow-up" (odeSolve (\_, [y] => [y * y]) [1.0] 0.0 2.0) $ \s => do
    putStrLn $ "blow-up solved up to: " ++ fixed (snd (domain s))
    putStrLn $ "stop reason given: " ++ show (map (Data.String.isPrefixOf "stopped at t = ") (stopReason s))
    putStrLn $ "at t = 0.5: " ++ showM (sample s 0.5) ++ ", at t = 1.5: " ++ showM (sample s 1.5)

  -- backwards in time: y' = y from t = 0 to t = -1
  report "backwards" (odeSolve (\_, [y] => [y]) [1.0] 0.0 (-1.0)) $ \s =>
    putStrLn $ "backwards: " ++ show (domain s) ++ ", y(-1) = " ++ showM (sample s (-1.0))

  -- 6. failures come back as Left, with WL's reason
  report "NaN right-hand side" (odeSolve (\_, [y] => [0.0 / 0.0]) [1.0] 0.0 1.0) $ \_ =>
    putStrLn "NaN right-hand side: solved?"
  report "unknown parameter" (odeSolveSym "t" ["y"] [var "a" * var "y"] [1.0] 0.0 1.0) $ \_ =>
    putStrLn "unknown parameter: solved?"

  -- 7. three bodies chasing each other around a figure eight
  report "figure eight" (odeSolve threeBody figureEight 0.0 6.32591398) $ \s =>
    putStrLn $ "figure eight back at the start after one period: "
      ++ show (map (\y => distance y figureEight < 1.0e-3) (sample s 6.32591398))
