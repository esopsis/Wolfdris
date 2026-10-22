module Main

import Data.Bits
import Data.IOArray
import Data.IORef
import System.Info

main : IO ()
main = do
  -- IORef
  r <- newIORef (the Integer 0)
  traverse_ (\i => modifyIORef r (+ i)) [1 .. 100]
  readIORef r >>= printLn
  -- IOArray (elements are Maybe)
  arr <- newArray {elem = String} 5
  ignore $ writeArray arr 2 "two"
  readArray arr 2 >>= printLn
  readArray arr 0 >>= printLn
  printLn (max arr)
  -- bits
  printLn (shiftL (the Bits8 0xF0) 2, shiftR (the Bits8 0xF0) 4)
  printLn (shiftR (the Int (-16)) 2, shiftL (the Int 1) 63)
  printLn (the Bits16 0xF0F0 .&. 0xFF00, the Bits16 0xF0F0 .|. 0x000F)
  printLn (xor (the Int32 0x0FF0) 0x00FF, complement (the Bits8 0x0F))
  printLn (shiftL (the Integer 1) 100, popCount (the Bits32 0xFF00FF))
  -- stdin (tests/effects/input), then end of input
  name <- getLine
  putStrLn ("hello, " ++ name)
  getLine >>= printLn
  getLine >>= printLn
  -- the backend name differs; just check it's one of ours
  printLn (codegen == "chez" || codegen == "wolfram")
