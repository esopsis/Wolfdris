||| Symbolic expressions: Idris builds them, WL does the calculus.
|||
||| `Expr` is a generic tree of WL expressions, so every result WL returns
||| converts back, even with functions Idris doesn't model. But its
||| constructors are not exported: expressions are built only through the
||| typed functions below (right arities, known heads), and inspected
||| through the read-only `View`. To build with a WL function not covered
||| here, define it in one line with Wolfram.Symbolic.Unsafe.
module Wolfram.Symbolic

import Data.List
import Data.Vect
import Wolfram.FFI

%default total

export
data Expr = Sym String               -- a WL symbol: Plus, Sin, Pi, Global`y, ...
          | Var String               -- a variable of the program
          | IntE Integer
          | RealE Double
          | Str String
          | App Expr (List Expr)     -- h[args]
          | Raw WLExpr               -- any other WL atom (images, sparse arrays, ...)

%foreign "wolfram:WolfdrisRT`dSym"
prim__dSym : Desc Expr

||| Every WL expression converts, so `fromWL` never fails for `Expr`.
export
Marshal Expr where
  desc = prim__dSym

%foreign "wolfram:WolfdrisRT`symString"
prim__symString : WLExpr -> String

||| WL's InputForm, e.g. `x^2*Sin[x]`; parenthesised as an argument
||| (`Just (x + 1)`) unless it is a single name or number.
export
Show Expr where
  show e = prim__symString (toWL e)
  showPrec d e = let s = show e in showParens (d >= App && any special (unpack s)) s
    where
      special : Char -> Bool
      special c = not (isAlphaNum c || c == '$' || c == '`' || c == '.')

-- A foreign Bool must be 0/1 (the runtime representation), not True/False
%foreign "wolfram:(Boole[SameQ[#1, #2]] &)"
prim__sameQ : WLExpr -> WLExpr -> Bool

||| Structural equality. WL results are canonical, so compare them after
||| `wlSimplify` or `wlExpand` to test mathematical equality.
export
Eq Expr where
  a == b = prim__sameQ (toWL a) (toWL b)

-- ---- Building ----

app : String -> List Expr -> Expr
app h = App (Sym h)

||| A variable. A plain name (`var "x"`) is the program's own; a symbol
||| from a notebook arrives as a variable named by its full name
||| (`Global`x`), so results come back in the caller's own symbols.
export
var : String -> Expr
var = Var

||| The name of a variable, if the expression is one: for exports that take
||| "the variable" as an argument (`deriv[expr, x]`).
export
varName : Expr -> Maybe String
varName (Var v) = Just v
varName _ = Nothing

export
Num Expr where
  fromInteger = IntE
  a + b = app "Plus" [a, b]
  a * b = app "Times" [a, b]

export
Neg Expr where
  negate a = app "Times" [IntE (-1), a]
  a - b = app "Plus" [a, negate b]

export
Abs Expr where
  abs a = app "Abs" [a]

export
Fractional Expr where
  a / b = app "Times" [a, app "Power" [b, IntE (-1)]]
  recip a = app "Power" [a, IntE (-1)]

export
FromDouble Expr where
  fromDouble = RealE

-- Tighter than * and / (infixl 9) and + and - (infixl 8)
export infixr 10 ^

||| Power.
export
(^) : Expr -> Expr -> Expr
a ^ b = app "Power" [a, b]

export sqrt : Expr -> Expr
sqrt a = app "Sqrt" [a]
export exp : Expr -> Expr
exp a = app "Exp" [a]
export log : Expr -> Expr
log a = app "Log" [a]
export sin : Expr -> Expr
sin a = app "Sin" [a]
export cos : Expr -> Expr
cos a = app "Cos" [a]
export tan : Expr -> Expr
tan a = app "Tan" [a]
export asin : Expr -> Expr
asin a = app "ArcSin" [a]
export acos : Expr -> Expr
acos a = app "ArcCos" [a]
export atan : Expr -> Expr
atan a = app "ArcTan" [a]
export sinh : Expr -> Expr
sinh a = app "Sinh" [a]
export cosh : Expr -> Expr
cosh a = app "Cosh" [a]
export tanh : Expr -> Expr
tanh a = app "Tanh" [a]

||| π, e and the imaginary unit.
export pi : Expr
pi = Sym "Pi"
export euler : Expr
euler = Sym "E"
export imagI : Expr
imagI = Sym "I"

-- ---- Inspecting ----

||| The functions `View` names. Anything else is `VOther`.
public export
data Func = Sin | Cos | Tan | ArcSin | ArcCos | ArcTan | Sinh | Cosh | Tanh
          | Exp | Log | Abs

export
Show Func where
  show Sin = "Sin"; show Cos = "Cos"; show Tan = "Tan"
  show ArcSin = "ArcSin"; show ArcCos = "ArcCos"; show ArcTan = "ArcTan"
  show Sinh = "Sinh"; show Cosh = "Cosh"; show Tanh = "Tanh"
  show Exp = "Exp"; show Log = "Log"; show Abs = "Abs"

funcs : List (String, Func)
funcs = [ ("Sin", Sin), ("Cos", Cos), ("Tan", Tan), ("ArcSin", ArcSin)
        , ("ArcCos", ArcCos), ("ArcTan", ArcTan), ("Sinh", Sinh)
        , ("Cosh", Cosh), ("Tanh", Tanh), ("Exp", Exp), ("Log", Log)
        , ("Abs", Abs) ]

||| The top level of an expression, read-only. (WL writes square roots as
||| powers, `Sqrt[x]` is `Power[x, 1/2]`, and `Exp[x]` as `Power[E, x]`.)
public export
data View = VVar String
          | VInt Integer
          | VRat Integer Integer
          | VReal Double
          | VComplex Expr Expr
          | VStr String
          | VConst String               -- Pi, E, ...
          | VAdd (List Expr)
          | VMul (List Expr)
          | VPow Expr Expr
          | VFn Func (List Expr)
          | VOther String (List Expr)   -- a head Idris doesn't model, by name
          | VAtom                       -- some other WL atom

export
view : Expr -> View
view (Var v) = VVar v
view (IntE n) = VInt n
view (RealE r) = VReal r
view (Str s) = VStr s
view (Raw _) = VAtom
view (Sym s) = VConst s
view (App (Sym "Rational") [IntE a, IntE b]) = VRat a b
view (App (Sym "Complex") [a, b]) = VComplex a b
view (App (Sym "Plus") ts) = VAdd ts
view (App (Sym "Times") ts) = VMul ts
view (App (Sym "Power") [a, b]) = VPow a b
view (App (Sym h) args) = maybe (VOther h args) (\f => VFn f args) (lookup h funcs)
view (App h args) = VOther (show h) args
