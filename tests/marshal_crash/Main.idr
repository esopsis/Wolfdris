module Main

import Wolfram.FFI

-- Golden test (wolfram only): a WL value of the wrong shape crashes,
-- naming the expected type and the part that didn't fit.

%foreign "wolfram:ToExpression"
parse : String -> WLExpr

main : IO ()
main = do
  putStrLn "before"
  printLn (the (List Integer) (fromWL (parse "{1, 2, x}")))
  putStrLn "not reached"
