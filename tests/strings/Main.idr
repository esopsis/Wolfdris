module Main

import Data.String

main : IO ()
main = do
  let s = "Hello, World"
  putStrLn (s ++ "!")
  printLn (length s)
  putStrLn (reverse s)
  putStrLn (substr 7 5 s)
  printLn (unpack "abc")
  putStrLn (pack ['x', 'y', 'z'])
  printLn (show (the Int (-42)))
  printLn "tab\there \"quoted\" back\\slash"
  putStrLn "αβγ ☃"
  printLn (words "the quick  brown fox")
  putStrLn (toUpper "shout")
  printLn (map ord (unpack "Az"))
  printLn (cast {to = Integer} "12345", cast {to = Int} "nope")
  printLn ("apple" < "banana", "b" < "ab", "same" == "same")
