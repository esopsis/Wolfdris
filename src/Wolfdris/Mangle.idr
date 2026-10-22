||| Turning Idris names and literals into Wolfram Language source text.
module Wolfdris.Mangle

import Core.Name
import Core.Name.Namespace
import Data.List
import Data.String

%default covering

||| Context for generated definitions and locals.
export
genContext : String
genContext = "WolfdrisGen`"

||| Context for the runtime library (support/wolfram/runtime.wl).
export
rtContext : String
rtContext = "WolfdrisRT`"

||| A runtime symbol, e.g. `rt "unit"` is "WolfdrisRT`unit".
export
rt : String -> String
rt s = rtContext ++ s

hexDigit : Int -> Char
hexDigit d = if d < 10 then chr (ord '0' + d) else chr (ord 'a' + d - 10)

export
hex : Int -> String
hex n = if n < 16 then singleton (hexDigit n)
                  else hex (n `div` 16) ++ singleton (hexDigit (n `mod` 16))

padHex : Nat -> Int -> String
padHex w n = let h = hex n in replicate (w `minus` length h) '0' ++ h

||| An injective rendering of a Name as a string. Unlike `show`, it ignores
||| the display string of `DN` and marks every machine-generated form.
export
nameStr : Name -> String
nameStr (NS ns n) = showNSWithSep "." ns ++ "." ++ nameStr n
nameStr (UN (Basic s)) = s
nameStr (UN (Field s)) = "." ++ s
nameStr (UN Underscore) = "_"
nameStr (MN s i) = "{" ++ s ++ ":" ++ show i ++ "}"
nameStr (PV n i) = "{P:" ++ nameStr n ++ ":" ++ show i ++ "}"
nameStr (DN _ n) = nameStr n
nameStr (Nested (a, b) n) = "{N:" ++ show a ++ ":" ++ show b ++ ":" ++ nameStr n ++ "}"
nameStr (CaseBlock s i) = "{C:" ++ s ++ ":" ++ show i ++ "}"
nameStr (WithBlock s i) = "{W:" ++ s ++ ":" ++ show i ++ "}"
nameStr (Resolved i) = "{R:" ++ show i ++ "}"

||| Escape a string into WL symbol characters: ASCII letters and digits are
||| kept, anything else becomes `$<hex>$`. `$` itself is always escaped, so
||| the encoding is injective.
symEscape : String -> String
symEscape = concatMap esc . unpack
  where
    esc : Char -> String
    esc c = if isAlphaNum c && ord c < 128
               then singleton c
               else "$" ++ hex (ord c) ++ "$"

||| Symbol for a top-level definition.
export
globalSym : Name -> String
globalSym n = genContext ++ "f" ++ symEscape (nameStr n)

||| Symbol for a local variable (function argument, lambda or let binder).
export
localSym : Name -> String
localSym n = genContext ++ "v" ++ symEscape (nameStr n)

||| Symbol for the i-th scrutinee temporary.
export
scrutSym : Int -> String
scrutSym i = genContext ++ "s" ++ show i

||| A WL string literal. Output is pure ASCII: everything outside printable
||| ASCII becomes `\:XXXX`, or `\|XXXXXX` above U+FFFF.
export
wlString : String -> String
wlString s = "\"" ++ concatMap esc (unpack s) ++ "\""
  where
    esc : Char -> String
    esc '\\' = "\\\\"
    esc '"' = "\\\""
    esc '\n' = "\\n"
    esc '\t' = "\\t"
    esc '\r' = "\\r"
    esc c = let n = ord c in
            if n >= 32 && n < 127 then singleton c
            else if n <= 0xFFFF then "\\:" ++ padHex 4 n
            else "\\|" ++ padHex 6 n

||| A WL literal for an Idris Double. Finite values become machine-real
||| literals: `show` (chez's shortest round-trip digits, e.g. "1.5e-7" or
||| "5e-324|1") with a backtick so WL never reads them as arbitrary
||| precision. NaN and the infinities use WL's own values, as the runtime does.
export
wlDouble : Double -> String
wlDouble d =
  if d /= d then "Indeterminate"
  else if d == 1.0 / 0.0 then "Infinity"
  else if d == -1.0 / 0.0 then "DirectedInfinity[-1]"
  else
    let s = fst (break (== '|') (show d))
        (mant, ex) = break (== 'e') s
        mant' = if isInfixOf "." mant then mant else mant ++ "."
    in case strM ex of
            StrNil => mant' ++ "`"
            StrCons _ rest => mant' ++ "`*^" ++ rest
