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
  , ("Prelude.IO.prim__getChar", "getChar")
  , ("Prelude.Types.fastPack", "fastPack")
  , ("Prelude.Types.fastUnpack", "fastUnpack")
  , ("Prelude.Types.fastConcat", "fastConcat")
  , ("Data.Double.nan", "doubleNaN")
  , ("Data.Double.inf", "doubleInf")
  , ("Data.Double.epsilon", "doubleEpsilon")
  , ("Data.Double.unitRoundoff", "doubleUnitRoundoff")
  -- pointers
  , ("PrimIO.prim__nullAnyPtr", "isNullPtr")
  , ("PrimIO.prim__getNullAnyPtr", "nullPtrConst")
  , ("Prelude.IO.prim__getString", "getString")
  , ("System.FFI.prim__free", "freePtr")
  -- System
  , ("System.prim__exit", "exit")
  , ("System.prim__getArgCount", "argCount")
  , ("System.prim__getArg", "getArg")
  , ("System.prim__getEnv", "getEnv")
  , ("System.prim__getEnvPair", "getEnvPair")
  , ("System.prim__setEnv", "setEnv")
  , ("System.prim__unsetEnv", "unsetEnv")
  , ("System.prim__time", "unixTime")
  , ("System.prim__getPID", "getPID")
  , ("System.prim__sleep", "sleepSec")
  , ("System.prim__usleep", "sleepMicro")
  , ("System.Info.prim__getNProcessors", "nProcessors")
  , ("System.Term.prim__setupTerm", "termSetup")
  , ("System.Term.prim__getTermCols", "termZero")
  , ("System.Term.prim__getTermLines", "termZero")
  , ("System.Errno.prim__getErrno", "getErrno")
  , ("System.Errno.prim__strerror", "strerror")
  -- System.File
  , ("System.File.Handle.prim__open", "openFile")
  , ("System.File.Handle.prim__close", "closeFile")
  , ("System.File.ReadWrite.prim__seekLine", "seekLine")
  , ("System.File.ReadWrite.prim__readLine", "readLine")
  , ("System.File.ReadWrite.prim__readChars", "readChars")
  , ("System.File.ReadWrite.prim__readChar", "readChar")
  , ("System.File.ReadWrite.prim__writeLine", "writeLine")
  , ("System.File.ReadWrite.prim__eof", "fileEOF")
  , ("System.File.ReadWrite.prim__removeFile", "removeFile")
  , ("System.File.Error.prim__error", "fileError")
  , ("System.File.Error.prim__fileErrno", "fileErrno")
  , ("System.File.Virtual.prim__stdin", "stdinFile")
  , ("System.File.Virtual.prim__stdout", "stdoutFile")
  , ("System.File.Virtual.prim__stderr", "stderrFile")
  , ("System.File.Meta.prim__fileSize", "fileSize")
  , ("System.File.Meta.prim__fPoll", "fileSize")
  , ("System.File.Meta.prim__fileIsTTY", "fileIsTTY")
  , ("System.File.Process.prim__flush", "flushFile")
  -- System.Directory
  , ("System.Directory.prim__currentDir", "currentDir")
  , ("System.Directory.prim__changeDir", "changeDir")
  , ("System.Directory.prim__createDir", "createDir")
  , ("System.Directory.prim__openDir", "openDir")
  , ("System.Directory.prim__closeDir", "closeDir")
  , ("System.Directory.prim__removeDir", "removeDir")
  , ("System.Directory.prim__dirEntry", "dirEntry")
  -- System.Clock (scheme-only foreigns)
  , ("System.Clock.prim__clockTimeMonotonic", "clockMonotonic")
  , ("System.Clock.prim__clockTimeUtc", "clockUtc")
  , ("System.Clock.prim__clockTimeProcess", "clockCpu")
  , ("System.Clock.prim__clockTimeThread", "clockCpu")
  , ("System.Clock.prim__clockTimeGcCpu", "clockZero")
  , ("System.Clock.prim__clockTimeGcReal", "clockZero")
  , ("System.Clock.prim__osClockValid", "clockValid")
  , ("System.Clock.prim__osClockSecond", "clockSecond")
  , ("System.Clock.prim__osClockNanosecond", "clockNanosecond")
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
