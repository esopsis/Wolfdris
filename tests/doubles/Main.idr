module Main

import Data.Double

-- Avoids results that are -0.0 in chez: WL has no signed zero (accepted
-- divergence, see CLAUDE.md). Uses typed lists, not long tuples, to keep
-- elaboration cheap.

ds : List Double -> IO ()
ds = printLn

bs : List Bool -> IO ()
bs = printLn

main : IO ()
main = do
  ds [0.1 + 0.2, 1.0 / 3.0]
  ds [1.0, 100.0, 1.0e10, 1.0e9, 0.001, 1.0e-4, 123.456, 1.5e-7, 2.5e300]
  ds [1.0e308 * 10.0, -1.0e308 * 10.0]
  ds [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0]
  ds [inf - inf, inf * 0.0, 1.0 / inf, nan + 1.0]
  ds [sqrt 2.0, sqrt (-1.0), exp 1.0, log 10.0, log 0.0, log (-1.0)]
  ds [sin 1.0, cos 1.0, tan 1.0, asin 0.5, acos 2.0, atan inf]
  ds [floor 2.5, ceiling (-2.5), floor (-2.5), floor inf]
  ds [pow 2.0 0.5, pow 2.0 1024.0, pow (-8.0) (1.0 / 3.0), pow (-2.0) 3.0]
  ds [pow 0.0 (-1.0), pow nan 0.0, pow 1.0 nan, pow 0.5 inf, pow (-inf) 3.0]
  ds [exp 1000.0, exp (-1000.0), 5.0e-324, 2.2250738585072014e-308 / 3.0]
  let pt1 = the Double 0.1
      pt3 = the Double 0.3
  bs [nan == nan, nan < 1.0, inf > 1.0e308, pt1 + 0.2 == pt3, pt3 < pt1 + 0.2]
  printLn [cast {to = Integer} (the Double 2.9), cast {to = Integer} (the Double (-2.9))]
  printLn (cast {to = Int} (the Double 1.0e20))
  ds [cast (the Integer 12345678901234567891)]
  ds [cast "3.25", cast "1.0e400", cast "junk", cast "0.1", cast "-12.5e-3", cast "+inf.0"]
  putStrLn (show (the Double (-2.5)))
  ds [negate 0.5, 1.0e22, 9007199254740993.0]
  ds [epsilon, unitRoundoff]
