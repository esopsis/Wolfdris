module Main

import Data.List
import Data.String
import Wolfram.Data
import Wolfram.FFI

-- Real-world data: import a CSV and a JSON file with WL, turn every row
-- into a typed Idris record or reject it with a reason, aggregate with WL.
-- Golden test (wolfram only): see `expected`.

data Region = North | South | East | West

Eq Region where
  North == North = True
  South == South = True
  East == East = True
  West == West = True
  _ == _ = False

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

-- A region is a string in WL, checked on the way in
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

record Address where
  constructor MkAddress
  city : String
  zip : Maybe String

Marshal Address where
  desc = record2 ("city", "zip") MkAddress (\a => (a.city, a.zip))

record Person where
  constructor MkPerson
  name : String
  age : Maybe Nat
  address : Address

Marshal Person where
  desc = record3 ("name", "age", "address") MkPerson (\p => (p.name, p.age, p.address))

||| Six decimals (for non-negative numbers): WL's last digits aren't specified.
fixed6 : Double -> String
fixed6 d = let n = cast {to = Integer} (floor (d * 1000000.0 + 0.5))
               frac = show (n `mod` 1000000) in
           show (n `div` 1000000) ++ "." ++ pack (replicate (minus 6 (length frac)) '0') ++ frac

total' : List Sale -> Double
total' = sum . map amount

reportRejected : List (Nat, String) -> String -> IO ()
reportRejected bad what = for_ bad $ \(i, e) => putStrLn ("  " ++ what ++ " " ++ show i ++ ": " ++ e)

main : IO ()
main = do
  Right rows <- wlImportCSV "sales.csv"
    | Left e => putStrLn ("import failed: " ++ e)
  let (sales, bad) = validateRows {r = Sale} rows
  putStrLn $ "loaded " ++ show (length sales) ++ " sales, rejected " ++ show (length bad) ++ ":"
  reportRejected bad "line"
  putStrLn $ "first sale, back in WL: " ++ show (toWL (take 1 sales))
  putStrLn $ "sales without a note: " ++ show (length (filter (isNothing . note) sales))
  -- WL groups; the totals are checked against plain Idris
  let byRegion = wlGroupBy region sales
  for_ byRegion $ \(r, ss) =>
    putStrLn $ "  " ++ show r ++ ": " ++ show (length ss)
      ++ (if length ss == 1 then " sale" else " sales") ++ ", total "
      ++ fixed6 (total' ss) ++ ", mean " ++ maybe "-" fixed6 (wlMean (map amount ss))
  putStrLn $ "totals agree with Idris: "
    ++ show (all (\(r, ss) => total' ss == total' (filter ((== r) . region) sales)) byRegion)
  for_ (wlGroupBy year sales) $ \(y, ss) =>
    putStrLn $ "  " ++ show y ++ ": total " ++ fixed6 (total' ss)
      ++ ", median " ++ maybe "-" fixed6 (wlMedian (map amount ss))
  putStrLn $ "mean of nothing: " ++ show (wlMean [])
  ok <- wlExportBarChart "build/sales.png" (map (\(r, ss) => (show r, total' ss)) byRegion)
  putStrLn $ "chart exported: " ++ show ok
  -- JSON: nested records, null and missing fields
  Right json <- wlImportJSON "people.json"
    | Left e => putStrLn ("import failed: " ++ e)
  let (people, badPeople) = validateItems {r = Person} (fromWL json)
  for_ people $ \p =>
    putStrLn $ "  " ++ p.name ++ " (" ++ maybe "age unknown" show p.age ++ ") in "
      ++ p.address.city ++ maybe "" (" " ++) p.address.zip
  putStrLn $ "rejected " ++ show (length badPeople) ++ " people:"
  reportRejected badPeople "item"
  missing <- wlImportCSV "no-such-file.csv"
  putStrLn $ "a missing file: " ++ either id (const "imported?") missing
