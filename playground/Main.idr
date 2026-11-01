module Main

import Data.Vect
import Wolfram.LinAlg

-- Try the editor here: hover a name to see its type, or put the cursor on
-- `xs` in `describe` and ask for a case split.

||| A 2 × 2 system: 2x + y = 5, x - y = 1.
a : Matrix 2 2
a = [[2.0, 1.0], [1.0, -1.0]]

b : Vect 2 Double
b = [5.0, 1.0]

describe : List Double -> String
describe xs = ?describe_rhs

main : IO ()
main = printLn (linearSolve a b)
