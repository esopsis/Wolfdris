||| Runs Idris 2's own tests against the wolfram backend.
|||
||| scripts/conformance.sh copies the chosen test directories into
||| build/conformance/tests, prunes them, and runs this from there. Every
||| directory that still holds tests becomes a pool with codegen = Default,
||| so the runner's `--cg wolfram` reaches every test's `run` script.
module Runner

import Data.List
import Data.String
import System
import System.Directory
import System.File
import Test.Golden

%default covering

||| Top-level test directories; idris2/ has one more level of grouping.
topDirs : List String
topDirs = ["chez", "allschemes", "allbackends", "base", "prelude", "contrib"]

subdirs : String -> IO (List String)
subdirs dir = do
  Right names <- listDir dir
    | Left _ => pure []
  pure $ sort [dir ++ "/" ++ n | n <- names, n /= ".", n /= ".."]

isTest : String -> IO Bool
isTest dir = exists (dir ++ "/run")

pool : String -> IO (Maybe TestPool)
pool dir = do
  tests <- filterM isTest !(subdirs dir)
  pure $ if null tests then Nothing
         else Just (MkTestPool dir [] Default tests)
  where
    filterM : (a -> IO Bool) -> List a -> IO (List a)
    filterM p [] = pure []
    filterM p (x :: xs) = if !(p x) then (x ::) <$> filterM p xs else filterM p xs

main : IO ()
main = do
  idrisGroups <- subdirs "idris2"
  pools <- traverse pool (topDirs ++ idrisGroups)
  runner (catMaybes pools)
