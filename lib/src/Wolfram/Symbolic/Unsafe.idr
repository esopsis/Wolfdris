||| Building expressions with any WL head, by name. Unchecked: you vouch
||| that the name exists and takes these arguments. Use it to define a
||| typed builder in one line, then use that:
|||
|||     besselJ : Expr -> Expr -> Expr
|||     besselJ n x = apply "BesselJ" [n, x]
module Wolfram.Symbolic.Unsafe

import Wolfram.FFI
import Wolfram.Symbolic

%default total

-- A bare name means the System` symbol if there is one (namedSymbol)
%foreign "wolfram:(WolfdrisRT`namedSymbol[#1] @@ #2 &)"
prim__apply : String -> WLExpr -> WLExpr

%foreign "wolfram:WolfdrisRT`namedSymbol"
prim__symbol : String -> WLExpr

||| `name[args...]`
export
apply : (name : String) -> List Expr -> Expr
apply h args = fromWL (prim__apply h (toWL args))

||| The WL symbol with this name, e.g. `symbol "EulerGamma"`.
export
symbol : String -> Expr
symbol s = fromWL (prim__symbol s)
