||| Resolving Idris foreign functions to Wolfram Language implementations.
|||
||| Lookup order: the table below (keyed by the full Idris name), then a
||| `wolfram:` spec on the declaration, else a compile-time error.
module Wolfdris.Foreign

import Core.Name
import Data.List
import Data.String
import Wolfdris.Mangle

%default covering

||| Idris name -> runtime function (in the WolfdrisRT` context). Runtime
||| functions receive every argument, including the world token.
foreignTable : List (String, String)
foreignTable =
  [ ("Prelude.IO.prim__putStr", "putStr")
  , ("Prelude.IO.prim__putChar", "putChar")
  , ("Prelude.IO.prim__getStr", "getStr")
  , ("Prelude.Types.fastPack", "fastPack")
  , ("Prelude.Types.fastUnpack", "fastUnpack")
  , ("Prelude.Types.fastConcat", "fastConcat")
  ]

export
lookupForeign : Name -> Maybe String
lookupForeign n = map rt (lookup (nameStr n) foreignTable)

||| The function named by a `wolfram:` spec, e.g. "wolfram:StringLength".
export
wolframSpec : List String -> Maybe String
wolframSpec specs = choiceMap spec specs
  where
    spec : String -> Maybe String
    spec s = let (cc, rest) = break (== ':') s in
             if trim cc == "wolfram"
                then Just (trim (substr 1 (length rest) rest))
                else Nothing
