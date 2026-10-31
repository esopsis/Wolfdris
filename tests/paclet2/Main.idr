module Main

import Data.List
import Data.Vect
import Wolfram.Calculus
import Wolfram.Data
import Wolfram.Export
import Wolfram.FFI
import Wolfram.Symbolic

-- A paclet a notebook can use with its own data, files and expressions
-- (scripts/paclet.sh builds it as SalesTools; driver.wl calls it).

data Region = North | South | East | West

Show Region where
  show North = "North"
  show South = "South"
  show East = "East"
  show West = "West"

parseRegion : String -> Either String Region
parseRegion "North" = Right North
parseRegion "South" = Right South
parseRegion "East" = Right East
parseRegion "West" = Right West
parseRegion s = Left ("unknown region " ++ show s)

Marshal Region where
  desc = refine parseRegion show desc

record Sale where
  constructor MkSale
  region : Region
  year : Nat
  amount : Double
  note : Maybe String

Marshal Sale where
  desc = record4 ("region", "year", "amount", "note") MkSale
                 (\s => (s.region, s.year, s.amount, s.note))

record Summary where
  constructor MkSummary
  loaded : Nat
  rejected : List String
  totals : List (String, Double)

Marshal Summary where
  desc = record3 ("loaded", "rejected", "totals") MkSummary
                 (\s => (s.loaded, s.rejected, s.totals))

||| totals[sales]: per-region totals of a list of sale associations.
totalsOf : List Sale -> List (String, Double)
totalsOf sales = map (\(r, ss) => (show r, sum (map amount ss))) (wlGroupBy region sales)

||| summarize[file]: read and validate a CSV of sales (IO).
summarize : String -> IO (Either String Summary)
summarize file = do
  Right rows <- importCSV file
    | Left e => pure (Left e)
  let (sales, bad) = validateRows {r = Sale} rows
  pure $ Right $ MkSummary (length sales)
                           (map (\(i, e) => "line " ++ show i ++ ": " ++ e) bad)
                           (totalsOf sales)

||| deriv[expr, x]: the derivative, in the caller's own symbols.
deriv : Expr -> Expr -> Either String Expr
deriv e x = case varName x of
  Just v => Right (wlD e v)
  Nothing => Left "the second argument must be a variable"

||| taylor[expr, x, n]: the n + 1 Taylor coefficients at 0.
taylorEntry : Expr -> Expr -> Nat -> Either String (List Expr)
taylorEntry e x n = case varName x of
  Nothing => Left "the second argument must be a variable"
  Just v => maybe (Left "no power series at 0") (Right . toList) (taylor n e v 0)

||| boomIO[n]: prints, then crashes for n > 0 (an IO export's crash is a
||| Failure too).
boomIO : Integer -> IO Integer
boomIO n = do
  putStrLn "boomIO is running"
  if n > 0 then assert_total (idris_crash "boom in IO") else pure n

main : IO ()
main = library
  [ fn1 "totals" "totals[sales] gives per-region totals of a list of sales." totalsOf
  , fnIO1 "summarize" "summarize[file] reads and validates a CSV of sales." summarize
  , fn2 "deriv" "deriv[expr, x] differentiates expr with respect to x." deriv
  , fn3 "taylor" "taylor[expr, x, n] gives the Taylor coefficients of expr at 0 up to x^n." taylorEntry
  , fnIO1 "boomIO" "boomIO[n] prints, then crashes for n > 0." boomIO ]
