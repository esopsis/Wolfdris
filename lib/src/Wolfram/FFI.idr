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

||| A complex number of Doubles; WL's `Complex[re, im]`.
public export
record Complex where
  constructor MkComplex
  re : Double
  im : Double

export
Eq Complex where
  MkComplex a b == MkComplex c d = a == c && b == d

||| `1.5+2.0i`, `1.5-2.0i`
export
Show Complex where
  show (MkComplex a b) = show a ++ (if b < 0 then "-" else "+") ++ show (abs b) ++ "i"

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

%foreign "wolfram:WolfdrisRT`dComplex"
prim__dComplex : Desc Complex

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

%foreign "wolfram:WolfdrisRT`dEither"
prim__dEither : Desc a -> Desc (Either String a)

%foreign "wolfram:WolfdrisRT`dMaybe"
prim__dMaybe : Desc a -> Desc (Maybe a)

-- field names and descriptors; t is the right-nested tuple of the fields
%foreign "wolfram:WolfdrisRT`dFields"
prim__dFields : WLExpr -> WLExpr -> Desc t

%foreign "wolfram:WolfdrisRT`dRefine"
prim__dRefine : Desc a -> (a -> Either String b) -> (b -> a) -> Desc b

%foreign "wolfram:WolfdrisRT`toWL"
prim__toWL : Desc a -> a -> WLExpr

%foreign "wolfram:WolfdrisRT`fromWL"
prim__fromWL : Desc a -> WLExpr -> a

%foreign "wolfram:WolfdrisRT`fromWLMaybe"
prim__fromWLMaybe : Desc a -> WLExpr -> Maybe a

%foreign "wolfram:WolfdrisRT`fromWLEither"
prim__fromWLEither : Desc a -> WLExpr -> Either String a

%foreign "wolfram:WolfdrisRT`fromText"
prim__fromText : Desc a -> WLExpr -> Either String a

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
||| Converting from WL accepts real numbers too (imaginary part 0).
export Marshal Complex where desc = prim__dComplex

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

||| `Right v` is `v` in WL; `Left msg` is `Failure["IdrisError", ...]` with
||| that message, as a crash gives. From WL, a `Failure` is a `Left`.
export
Marshal a => Marshal (Either String a) where
  desc = prim__dEither desc

||| `Nothing` is `Missing[]` in WL; from WL, `Missing[...]` and `Null` (and
||| `""` with `fromText`) are `Nothing`, anything else must be an `a`.
export
Marshal a => Marshal (Maybe a) where
  desc = prim__dMaybe desc

||| Idris to WL only: a WL function of one argument. A curried function
||| becomes a curried WL function; see `fun2` for two arguments.
export
(Marshal a, Marshal b) => Marshal (a -> b) where
  desc = prim__dFun desc desc

||| The descriptor itself, as a WL expression (for Wolfram.Export).
export
descExpr : Desc a -> WLExpr
descExpr = believe_me

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

||| A WL expression as an Idris value, or what's wrong with it, e.g.
||| `year: expected Nat, got -3`.
export
fromWLEither : Marshal a => WLExpr -> Either String a
fromWLEither = prim__fromWLEither desc

||| Like `fromWLEither`, for data that arrives as text (CSV): numbers may
||| be strings ("2021", "1e3"), and "" is `Nothing` for a `Maybe` field.
export
fromText : Marshal a => WLExpr -> Either String a
fromText = prim__fromText desc

-- ---- Records and validated types ----

||| Convert as `a`, then check and turn it into a `b`; the `Left` message
||| becomes the conversion error. The second function converts back.
|||
|||     Marshal Region where
|||       desc = refine parseRegion show desc
export
refine : (a -> Either String b) -> (b -> a) -> Desc a -> Desc b
refine from to d = prim__dRefine d from to

names : List String -> WLExpr
names = toWL

descs : List WLExpr -> WLExpr
descs = toWL

||| A record as a WL `Association` with these keys, given the record's
||| constructor and a function giving its fields as a tuple:
|||
|||     Marshal Sale where
|||       desc = record3 ("region", "year", "amount") MkSale
|||                      (\s => (s.region, s.year, s.amount))
|||
||| Extra keys are ignored; a missing key is an error unless the field is a
||| `Maybe`; errors name the field (`year: expected Nat, got "-3"`).
export
record1 : Marshal a => String -> (a -> r) -> (r -> a) -> Desc r
record1 n mk get = refine (Right . mk) get
  (prim__dFields (names [n]) (descs [descExpr (desc {a})]))

export
record2 : (Marshal a, Marshal b) => (String, String) -> (a -> b -> r) -> (r -> (a, b)) -> Desc r
record2 (n1, n2) mk get = refine (\(x, y) => Right (mk x y)) get
  (prim__dFields (names [n1, n2]) (descs [descExpr (desc {a}), descExpr (desc {a = b})]))

export
record3 : (Marshal a, Marshal b, Marshal c) =>
          (String, String, String) -> (a -> b -> c -> r) -> (r -> (a, b, c)) -> Desc r
record3 (n1, n2, n3) mk get = refine (\(x, y, z) => Right (mk x y z)) get
  (prim__dFields (names [n1, n2, n3])
     (descs [descExpr (desc {a}), descExpr (desc {a = b}), descExpr (desc {a = c})]))

export
record4 : (Marshal a, Marshal b, Marshal c, Marshal d) =>
          (String, String, String, String) -> (a -> b -> c -> d -> r) ->
          (r -> (a, b, c, d)) -> Desc r
record4 (n1, n2, n3, n4) mk get = refine (\(x, y, z, w) => Right (mk x y z w)) get
  (prim__dFields (names [n1, n2, n3, n4])
     (descs [ descExpr (desc {a}), descExpr (desc {a = b}), descExpr (desc {a = c})
            , descExpr (desc {a = d}) ]))

export
record5 : (Marshal a, Marshal b, Marshal c, Marshal d, Marshal e) =>
          (String, String, String, String, String) -> (a -> b -> c -> d -> e -> r) ->
          (r -> (a, b, c, d, e)) -> Desc r
record5 (n1, n2, n3, n4, n5) mk get = refine (\(x, y, z, w, v) => Right (mk x y z w v)) get
  (prim__dFields (names [n1, n2, n3, n4, n5])
     (descs [ descExpr (desc {a}), descExpr (desc {a = b}), descExpr (desc {a = c})
            , descExpr (desc {a = d}), descExpr (desc {a = e}) ]))

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
