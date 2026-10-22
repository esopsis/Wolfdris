module Main

power : Integer -> Nat -> Integer
power b 0 = 1
power b (S k) = b * power b k

main : IO ()
main = do
  printLn (power 2 100)
  printLn (div (-7) 2, mod (-7) 2)
  printLn (div (-7) (-2), mod (-7) (-2))
  printLn (div 7 (-2), mod 7 (-2))
  printLn (div (the Int (-7)) 2, mod (the Int (-7)) (-2))
  printLn (the Int 9223372036854775807 + 1)
  printLn (the Bits8 250 + 10)
  printLn (the Int8 127 + 1)
  printLn (the Bits16 0 - 1)
  printLn (compare (the Integer 3) 5, the Integer 3 < 5, the Int 4 == 4)
  printLn (cast {to = Int} (power 2 70))
  printLn (negate (the Integer 12345678901234567890))
  printLn (the Integer (-17) * 3 - 2)
