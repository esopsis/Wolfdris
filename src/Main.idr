module Main

import Compiler.Common
import Idris.Driver
import Wolfdris.Codegen

main : IO ()
main = mainWithCodegens [("wolfram", codegenWolfram)]
