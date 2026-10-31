||| Data in, typed records out: import CSV/JSON with WL, validate every row
||| into an Idris record (or a reason it was rejected), aggregate with WL.
|||
||| Records declare their WL shape with Wolfram.FFI's recordN; see
||| tests/data for a worked example.
module Wolfram.Data

import Data.List
import Wolfram.FFI

%default total

-- Glue results are {"ok", value} or {"error", message}
okOrError : WLExpr -> Either String WLExpr
okOrError r = case the (String, WLExpr) (fromWL r) of
  ("ok", v) => Right v
  (_, msg) => Left (fromWL msg)

-- Every value as text ("Numeric" -> False): WL guesses CSV types per
-- column, so one bad cell would turn a whole column of numbers into
-- strings. Text keeps a value's meaning independent of other rows;
-- fromText parses it as the record's field type says.
%foreign "wolfram:(Quiet[Check[With[{rows = Import[#, \"CSV\", \"Numeric\" -> False]}, If[MatchQ[rows, {_List, ___}], {\"ok\", AssociationThread[Take[First[rows], UpTo[Length[#]]], Take[#, UpTo[Length[First[rows]]]]] & /@ Rest[rows]}, {\"error\", \"not a CSV file with a header row: \" <> #}]], {\"error\", \"could not import \" <> #}]] &)"
prim__importCSV : String -> PrimIO WLExpr

%foreign "wolfram:(Quiet[Check[{\"ok\", Import[#, \"RawJSON\"]}, {\"error\", \"could not import \" <> #}]] &)"
prim__importJSON : String -> PrimIO WLExpr

||| The rows of a CSV file with a header row, each as an association keyed
||| by the header. All values are text; validate them with `validateRows`.
export
importCSV : HasIO io => (file : String) -> io (Either String (List WLExpr))
importCSV f = pure (okOrError !(primIO (prim__importCSV f)) >>= fromWLEither)

||| A JSON file (objects become associations, null is Null).
export
importJSON : HasIO io => (file : String) -> io (Either String WLExpr)
importJSON f = pure (okOrError !(primIO (prim__importJSON f)))

||| Convert CSV rows (from `importCSV`) into records: the good ones, and
||| for each rejected row its line in the file (the header is line 1) and
||| the reason.
export
validateRows : Marshal r => List WLExpr -> (List r, List (Nat, String))
validateRows rows = go 2 rows
  where
    go : Nat -> List WLExpr -> (List r, List (Nat, String))
    go _ [] = ([], [])
    go i (x :: xs) = let (good, bad) = go (S i) xs in
                     case fromText x of
                       Right v => (v :: good, bad)
                       Left e => (good, (i, e) :: bad)

||| Like `validateRows`, for typed values (JSON): the good ones, and the
||| position (from 1) and reason for each rejected item.
export
validateItems : Marshal r => List WLExpr -> (List r, List (Nat, String))
validateItems items = go 1 items
  where
    go : Nat -> List WLExpr -> (List r, List (Nat, String))
    go _ [] = ([], [])
    go i (x :: xs) = let (good, bad) = go (S i) xs in
                     case fromWLEither x of
                       Right v => (v :: good, bad)
                       Left e => (good, (i, e) :: bad)

%foreign "wolfram:(KeyValueMap[List, GroupBy[#1, #2]] &)"
prim__groupBy : WLExpr -> WLExpr -> WLExpr

||| Group by a key (`GroupBy`), keys in order of first appearance.
export
wlGroupBy : (Marshal r, Marshal k) => (r -> k) -> List r -> List (k, List r)
wlGroupBy key xs = fromWL (prim__groupBy (toWL xs) (toWL key))

%foreign "wolfram:(If[# === {}, {}, {N[Mean[#]]}] &)"
prim__mean : WLExpr -> WLExpr

%foreign "wolfram:(If[# === {}, {}, {N[Median[#]]}] &)"
prim__median : WLExpr -> WLExpr

maybeOne : Marshal a => WLExpr -> Maybe a
maybeOne r = case the (List a) (fromWL r) of
  [x] => Just x
  _ => Nothing

||| The mean (`Mean`), or Nothing for no values.
export
mean : List Double -> Maybe Double
mean xs = maybeOne (prim__mean (toWL xs))

||| The median (`Median`), or Nothing for no values.
export
median : List Double -> Maybe Double
median xs = maybeOne (prim__median (toWL xs))

-- Bool results must be 0/1 at run time
%foreign "wolfram:(Boole[Quiet[Check[Export[#1, BarChart[#2[[All, 2]], ChartLabels -> #2[[All, 1]]]], $Failed]] =!= $Failed] &)"
prim__exportBarChart : String -> WLExpr -> PrimIO Bool

||| A bar chart of labelled values, exported to a file (`Export`; the
||| format follows the extension). False if WL couldn't. The first export
||| in a session starts WL's front end (several seconds).
export
exportBarChart : HasIO io => (file : String) -> List (String, Double) -> io Bool
exportBarChart f bars = primIO (prim__exportBarChart f (toWL bars))
