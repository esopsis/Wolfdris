module Main

import Data.Maybe

safeDiv : Integer -> Integer -> Maybe Integer
safeDiv _ 0 = Nothing
safeDiv a b = Just (a `div` b)

describe : Maybe Integer -> String
describe Nothing = "nothing"
describe (Just n) = "just " ++ show n

main : IO ()
main = do
  putStrLn (describe (safeDiv 10 2))
  putStrLn (describe (safeDiv 1 0))
  printLn (map (+ 1) (safeDiv 9 3))
  printLn (fromMaybe 0 (safeDiv 5 0))
  printLn (Just 3)
  printLn (the (Maybe Integer) Nothing)
  printLn (safeDiv 100 7 >>= safeDiv 1000)
  printLn (isJust (safeDiv 1 1), isNothing (safeDiv 1 0))
