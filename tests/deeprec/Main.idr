module Main

import Data.IORef
import Data.List
import Data.Nat
import Data.Stream
import Data.String

-- Recursion far deeper than WL's default $RecursionLimit (1024), through
-- code that is NOT tail recursive: ranges, foldr, user recursion, the Nat
-- comparisons, IO for_, lines/unlines, sort, zip.

sumR : List Integer -> Integer
sumR [] = 0
sumR (x :: xs) = x + sumR xs

countdown : Nat -> Nat
countdown Z = Z
countdown (S k) = S (countdown k)

main : IO ()
main = do
  printLn (foldr (+) 0 [1 .. 200000])
  printLn (sumR [1 .. 100000])
  printLn (countdown 100000)
  printLn (length (filter (\x => x `mod` 3 == 0) [1 .. 100000]))
  putStrLn $ case isLTE 20000 30000 of
    Yes _ => "20000 <= 30000"
    No _ => "isLTE is wrong"
  r <- newIORef (the Integer 0)
  for_ [1 .. 20000] $ \i => modifyIORef r (+ i)
  readIORef r >>= printLn
  printLn (length (take 4000 (repeat 'a')))
  let ls = map show [1 .. 20000]
  printLn (length (lines (unlines ls)))
  printLn (take 5 (sort (map (\x => (x * 7919) `mod` 20011) [1 .. 20000])))
  printLn (sum (map (\(a, b) => a * b) (zip [1 .. 20000] [1 .. 20000])))
