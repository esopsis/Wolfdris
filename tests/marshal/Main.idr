module Main

import Data.Vect
import Wolfram.FFI

-- Golden test (wolfram only): see `expected`.

%foreign "wolfram:ToExpression"
parse : String -> WLExpr

roundTrip : (Marshal a, Eq a) => a -> Bool
roundTrip x = fromWL (toWL x) == x

main : IO ()
main = do
  -- What WL sees
  printLn (toWL (the (List Integer) [1, 2, 3]))
  printLn (toWL (the (List Bool) [True, False]))
  printLn (toWL (the (List (Integer, String)) [(1, "a"), (2, "b")]))
  printLn (toWL (the (List (List Integer)) [[1], [], [2, 3]]))
  printLn (toWL (the (Vect 2 Double) [1.5, -0.25]))
  printLn (toWL (the (List Char) ['a', 'b']))
  printLn (toWL (the (List Nat) []))
  -- Round trips
  printLn (roundTrip (the Integer 1267650600228229401496703205376))
  printLn (roundTrip (the Int (-9223372036854775808)))
  printLn (roundTrip (the Nat 0))
  printLn (roundTrip (the Double 0.1))
  printLn (roundTrip "a\x3b1\x2603\nb")
  printLn (roundTrip '\x3b1')
  printLn (roundTrip (the (List Bool) [True, False, True]))
  printLn (roundTrip (the (List (List String)) [["x"], [], ["y", "z"]]))
  printLn (roundTrip (the (Vect 3 Integer) [1, 2, 3]))
  printLn (roundTrip (the (Integer, (String, Bool)) (1, ("p", False))))
  printLn (roundTrip (the (List Integer) [1 .. 20000]))
  -- From WL: numbers are converted, shapes are checked
  printLn (the Double (fromWL (parse "1/3")))
  printLn (the Double (fromWL (parse "Total[{1.*^308, 1.*^308}]")))
  printLn (the Double (fromWL (parse "0")))
  printLn (the (List Integer) (fromWL (parse "Range[5]")))
  printLn (the (Maybe Integer) (fromWLMaybe (parse "\"x\"")))
  printLn (the (Maybe (Vect 2 Integer)) (fromWLMaybe (parse "{1, 2, 3}")))
  printLn (the (Maybe (Vect 3 Integer)) (fromWLMaybe (parse "{1, 2, 3}")))
  printLn (the (Maybe Int) (fromWLMaybe (parse "2^63")))
  printLn (the (Maybe Nat) (fromWLMaybe (parse "-1")))
  printLn (the (Maybe Char) (fromWLMaybe (parse "\"ab\"")))
  printLn (the (Maybe Bool) (fromWLMaybe (parse "1 < 2")))
  printLn (the (Maybe String) (fromWLMaybe (parse "Missing[]")))
  printLn (the (Maybe (Integer, Integer)) (fromWLMaybe (parse "{1, 2}")))
