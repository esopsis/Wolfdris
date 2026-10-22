module Main

adder : Integer -> Integer -> Integer
adder x y = x + y

compose : (b -> c) -> (a -> b) -> a -> c
compose f g x = f (g x)

applyTwice : (a -> a) -> a -> a
applyTwice f x = f (f x)

main : IO ()
main = do
  let add3 = adder 3
  printLn (add3 4)
  let double = \x : Integer => x * 2
  printLn (map (compose add3 double) [1, 2, 3])
  printLn (applyTwice (adder 10) 1)
  let k = 5
  let addK = \x : Integer => x + k
  printLn (map addK [10, 20])
  printLn (foldr (\x, acc => x - acc) 0 [1, 2, 3, 4])
  printLn (map (\f => f 2) [adder 1, (* 3), compose double double])
