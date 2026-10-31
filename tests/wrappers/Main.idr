module Main

import Data.List
import Data.Vect
import Wolfram.FFI
import Wolfram.List

-- Golden test (wolfram only): see `expected`.

xs : Vect 10 Integer
xs = [5, 3, 8, 1, 9, 2, 7, 4, 6, 0]

main : IO ()
main = do
  let (p ** ys) = select (\x => x > 4) xs
  printLn (p, ys)
  -- a callback closing over a local
  let k = 3
  printLn (wlMap (\x => x * k) xs)
  printLn (wlMap (\x => cast {to = Double} x / 4.0) (take 3 xs))
  printLn (wlMap (\x => (x, show x)) (take 3 xs))
  printLn (wlMap toUpper (fromList (unpack "hello")))
  printLn (wlSort xs)
  -- Idris Ord, not WL's canonical order (which gives a, A, b, B)
  printLn (wlSort (the (Vect 4 String) ["b", "B", "a", "A"]))
  printLn (wlSort (the (Vect 3 Double) [2.5, -1.0, 0.5]))
  printLn (wlLength (the (List Double) [1.0, 2.0, 3.0]))
  printLn (wlLength (the (List String) []))
  printLn (wlTotal xs)
  printLn (wlTotal (the (Vect 3 Double) [0.5, 0.25, 0.125]))
  printLn (wlTotal (the (Vect 0 Double) []))
  -- Against the Idris equivalents, on bigger inputs
  let big = fromList (map (\i => (i * 7919) `mod` 20011) [1 .. 5000])
  printLn (toList (wlSort big) == sort (toList big))
  printLn (toList (snd (select (\x => x `mod` 3 == 0) big)) == filter (\x => x `mod` 3 == 0) (toList big))
  printLn (fst (select (\x => x `mod` 3 == 0) big) == length (filter (\x => x `mod` 3 == 0) (toList big)))
  printLn (toList (wlMap (+ 1) big) == map (+ 1) (toList big))
  printLn (wlTotal big == sum big)
  printLn (wlLength (toList big) == 5000)
