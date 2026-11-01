module Main

import Wolfram

-- Try the editor here: hover a name to see its type, or put the cursor on
-- `xs` in `describe` and ask for a case split (Ctrl+.).
-- `import Wolfram` brings in the whole wrapper library.

||| A 2 × 2 system: 2x + y = 5, x - y = 1.
a : Matrix 2 2
a = [[2.0, 1.0], [1.0, -1.0]]

b : Vect 2 Double
b = [5.0, 1.0]

x : Expr
x = var "x"

describe : List Double -> String
describe xs = ?describe_rhs

main : IO ()
main = do
  printLn (linearSolve a b)                  -- Wolfram.LinAlg
  printLn (integrate (x ^ 2 * sin x) "x")     -- Wolfram.Calculus
  printLn (mean [1.0, 2.0, 4.0])              -- Wolfram.Data
