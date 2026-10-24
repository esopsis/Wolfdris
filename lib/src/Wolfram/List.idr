||| The first typed wrappers around Wolfram Language list functions.
|||
||| Each one converts its arguments with `toWL`, calls the WL builtin, and
||| re-establishes what the type promises: lengths are measured or checked,
||| never assumed.
module Wolfram.List

import Data.Vect
import Wolfram.FFI

%default total

%foreign "wolfram:Select"
prim__select : WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:Map"
prim__map : WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:Sort"
prim__sort : WLExpr -> WLExpr -> WLExpr

%foreign "wolfram:Length"
prim__length : WLExpr -> WLExpr

%foreign "wolfram:Total"
prim__total : WLExpr -> WLExpr

||| The elements satisfying the predicate (`Select`). How many there are is
||| measured, not known in advance.
export
wlSelect : Marshal a => (a -> Bool) -> Vect n a -> (p ** Vect p a)
wlSelect p xs
    = let ys : List a = fromWL (prim__select (toWL (toList xs)) (toWL p)) in
      (_ ** fromList ys)

||| `Map`: the length is kept, and checked.
export
wlMap : (Marshal a, Marshal b) => (a -> b) -> Vect n a -> Vect n b
wlMap f xs = withLengthOf "wlMap" xs (fromWL (prim__map (toWL f) (toWL (toList xs))))

||| `Sort`, ordered by the Idris `Ord` instance (WL's own canonical order
||| differs, e.g. for strings). Stable, like Data.List.sort. The length is
||| checked.
export
wlSort : (Ord a, Marshal a) => Vect n a -> Vect n a
wlSort xs = withLengthOf "wlSort" xs (fromWL (prim__sort (toWL (toList xs)) (fun2 order)))
  where
    -- WL ordering functions return 1 if the arguments are in order
    order : a -> a -> Integer
    order x y = case compare x y of
      LT => 1
      EQ => 0
      GT => -1

||| `Length`.
export
wlLength : Marshal a => List a -> Nat
wlLength xs = fromWL (prim__length (toWL xs))

||| Element types `Total` can sum the way Idris would. Fixed-width integers
||| are excluded: WL's exact sum doesn't wrap around.
public export
interface Marshal a => WLNum a where

export WLNum Integer where
export WLNum Double where

||| `Total`. For Doubles the result is WL's sum, rounded to a Double.
export
wlTotal : WLNum a => Vect n a -> a
wlTotal xs = fromWL (prim__total (toWL (toList xs)))
