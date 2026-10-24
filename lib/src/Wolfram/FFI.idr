||| Marshalling between Idris values and Wolfram Language expressions.
|||
||| The conversion itself is done by the runtime (support/wolfram/runtime.wl,
||| "Marshalling"), driven by a descriptor of the Idris type. This module
||| only picks the descriptor for each type, through the `Marshal` interface.
module Wolfram.FFI

import public Data.Vect

%default total

||| Any Wolfram Language expression.
export
data WLExpr : Type where [external]

%foreign "wolfram:WolfdrisRT`exprString"
prim__exprString : WLExpr -> String

||| The expression in WL's InputForm.
export
Show WLExpr where
  show = prim__exprString

||| How to convert values of type `a`: an inert runtime expression.
export
data Desc : Type -> Type where [external]

%foreign "wolfram:WolfdrisRT`dInteger"
prim__dInteger : Desc Integer

%foreign "wolfram:WolfdrisRT`dInt"
prim__dInt : Desc Int

%foreign "wolfram:WolfdrisRT`dNat"
prim__dNat : Desc Nat

%foreign "wolfram:WolfdrisRT`dDouble"
prim__dDouble : Desc Double

%foreign "wolfram:WolfdrisRT`dString"
prim__dString : Desc String

%foreign "wolfram:WolfdrisRT`dChar"
prim__dChar : Desc Char

%foreign "wolfram:WolfdrisRT`dBool"
prim__dBool : Desc Bool

%foreign "wolfram:WolfdrisRT`dExpr"
prim__dExpr : Desc WLExpr

%foreign "wolfram:WolfdrisRT`dList"
prim__dList : Desc a -> Desc (List a)

-- Typed as a List descriptor: an erased Nat argument of a foreign function
-- would be passed to WL. Desc is a phantom, so retyping it is safe.
%foreign "wolfram:WolfdrisRT`dVect"
prim__dVect : Integer -> Desc a -> Desc (List a)

%foreign "wolfram:WolfdrisRT`dPair"
prim__dPair : Desc a -> Desc b -> Desc (a, b)

%foreign "wolfram:WolfdrisRT`dFun"
prim__dFun : Desc a -> Desc b -> Desc (a -> b)

%foreign "wolfram:WolfdrisRT`dFun2"
prim__dFun2 : Desc a -> Desc b -> Desc c -> Desc (a -> b -> c)

%foreign "wolfram:WolfdrisRT`toWL"
prim__toWL : Desc a -> a -> WLExpr

%foreign "wolfram:WolfdrisRT`fromWL"
prim__fromWL : Desc a -> WLExpr -> a

%foreign "wolfram:WolfdrisRT`fromWLMaybe"
prim__fromWLMaybe : Desc a -> WLExpr -> Maybe a

||| Types that can cross to Wolfram Language and back.
public export
interface Marshal a where
  desc : Desc a

export Marshal Integer where desc = prim__dInteger
||| Converting from WL checks the range rather than wrapping.
export Marshal Int where desc = prim__dInt
export Marshal Nat where desc = prim__dNat
export Marshal Double where desc = prim__dDouble
export Marshal String where desc = prim__dString
||| A Char is a one-character string in WL.
export Marshal Char where desc = prim__dChar
export Marshal Bool where desc = prim__dBool
export Marshal WLExpr where desc = prim__dExpr

export
Marshal a => Marshal (List a) where
  desc = prim__dList desc

||| Converting from WL checks the length.
export
{n : Nat} -> Marshal a => Marshal (Vect n a) where
  desc = believe_me (prim__dVect (natToInteger n) (desc {a}))

||| A pair is a two-element WL list.
export
(Marshal a, Marshal b) => Marshal (a, b) where
  desc = prim__dPair desc desc

||| Idris to WL only: a WL function of one argument. A curried function
||| becomes a curried WL function; see `fun2` for two arguments.
export
(Marshal a, Marshal b) => Marshal (a -> b) where
  desc = prim__dFun desc desc

||| An Idris value as a WL expression.
export
toWL : Marshal a => a -> WLExpr
toWL = prim__toWL desc

||| A WL expression as an Idris value; crashes, naming the expected type, if
||| it doesn't have the right shape.
export
fromWL : Marshal a => WLExpr -> a
fromWL = prim__fromWL desc

||| A WL expression as an Idris value, if it has the right shape.
export
fromWLMaybe : Marshal a => WLExpr -> Maybe a
fromWLMaybe = prim__fromWLMaybe desc

||| A two-argument Idris function as a WL function of two arguments
||| (`f[x, y]`), as WL builtins like `Sort` expect.
export
fun2 : (Marshal a, Marshal b, Marshal c) => (a -> b -> c) -> WLExpr
fun2 = prim__toWL (prim__dFun2 desc desc desc)

||| Re-establish the length the type promises for a WL result, crashing
||| (naming the wrapper) if WL didn't keep it.
export
withLengthOf : (wrapper : String) -> Vect n a -> List b -> Vect n b
withLengthOf _ [] [] = []
withLengthOf w (_ :: xs) (y :: ys) = y :: withLengthOf w xs ys
withLengthOf w _ _ = assert_total $ idris_crash (w ++ ": the result has the wrong length")
