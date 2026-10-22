module Main

import Data.List

sumList : List Integer -> Integer
sumList [] = 0
sumList (x :: xs) = x + sumList xs

-- Tail recursive: must not grow the WL stack.
countUp : Integer -> Integer -> Integer
countUp acc 0 = acc
countUp acc n = countUp (acc + n) (n - 1)

myLength : List a -> Nat
myLength [] = 0
myLength (_ :: xs) = S (myLength xs)

main : IO ()
main = do
  let xs = [1, 2, 3, 4, 5]
  printLn (sumList xs)
  printLn (countUp 0 100000)
  printLn (myLength xs)
  printLn (reverse xs)
  printLn (foldl (+) 0 [1..100])
  printLn (length (filter (> 2) xs))
  printLn (take 3 (drop 1 xs))
  printLn (zip [1, 2, 3] ["a", "b", "c"])
