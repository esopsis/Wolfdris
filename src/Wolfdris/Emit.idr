||| NamedCExp -> Wolfram Language source text.
|||
||| Every form that can hold a tail call (SetDelayed rhs, With, Switch,
||| Function) is one WL evaluates without growing the stack, so nothing here
||| may wrap a tail position in `;` (CompoundExpression) or Module.
module Wolfdris.Emit

import Core.CompileExpr
import Core.Context
import Core.Core
import Core.Name
import Core.TT
import Data.List
import Data.String
import Data.Vect
import Wolfdris.Foreign
import Wolfdris.Mangle

%default covering

||| Label for the counter that names scrutinee temporaries.
export
data Fresh : Type where

fresh : {auto f : Ref Fresh Int} -> Core Int
fresh = do i <- get Fresh
           put Fresh (i + 1)
           pure i

commas : List String -> String
commas = joinBy ", "

||| Keys of the runtime's primitive table: WolfdrisRT`op[keys...][args...].
opKeys : PrimFn arity -> List String
opKeys (Add ty) = ["Add", show ty]
opKeys (Sub ty) = ["Sub", show ty]
opKeys (Mul ty) = ["Mul", show ty]
opKeys (Div ty) = ["Div", show ty]
opKeys (Mod ty) = ["Mod", show ty]
opKeys (Neg ty) = ["Neg", show ty]
opKeys (ShiftL ty) = ["ShiftL", show ty]
opKeys (ShiftR ty) = ["ShiftR", show ty]
opKeys (BAnd ty) = ["BAnd", show ty]
opKeys (BOr ty) = ["BOr", show ty]
opKeys (BXOr ty) = ["BXOr", show ty]
opKeys (LT ty) = ["LT", show ty]
opKeys (LTE ty) = ["LTE", show ty]
opKeys (EQ ty) = ["EQ", show ty]
opKeys (GTE ty) = ["GTE", show ty]
opKeys (GT ty) = ["GT", show ty]
opKeys StrLength = ["StrLength"]
opKeys StrHead = ["StrHead"]
opKeys StrTail = ["StrTail"]
opKeys StrIndex = ["StrIndex"]
opKeys StrCons = ["StrCons"]
opKeys StrAppend = ["StrAppend"]
opKeys StrReverse = ["StrReverse"]
opKeys StrSubstr = ["StrSubstr"]
opKeys DoubleExp = ["DoubleExp"]
opKeys DoubleLog = ["DoubleLog"]
opKeys DoublePow = ["DoublePow"]
opKeys DoubleSin = ["DoubleSin"]
opKeys DoubleCos = ["DoubleCos"]
opKeys DoubleTan = ["DoubleTan"]
opKeys DoubleASin = ["DoubleASin"]
opKeys DoubleACos = ["DoubleACos"]
opKeys DoubleATan = ["DoubleATan"]
opKeys DoubleSqrt = ["DoubleSqrt"]
opKeys DoubleFloor = ["DoubleFloor"]
opKeys DoubleCeiling = ["DoubleCeiling"]
opKeys (Cast from to) = ["Cast", show from, show to]
opKeys BelieveMe = ["BelieveMe"]
opKeys Crash = ["Crash"]

constant : Constant -> String
constant (I x) = show x
constant (I8 x) = show x
constant (I16 x) = show x
constant (I32 x) = show x
constant (I64 x) = show x
constant (BI x) = show x
constant (B8 x) = show x
constant (B16 x) = show x
constant (B32 x) = show x
constant (B64 x) = show x
constant (Str s) = wlString s
constant (Ch c) = show (ord c)
constant (Db d) = wlDouble d
constant (PrT t) = wlString (show t)
constant WorldVal = rt "world"

||| Constructor tag: the numeric tag, or the constructor's name when Idris
||| gives none (matching chez, which uses the shown name).
tagLit : Name -> Maybe Int -> String
tagLit _ (Just t) = show t
tagLit n Nothing = wlString (nameStr n)

||| %extern primitives, by unqualified name, with their arguments already
||| emitted. Type arguments (erased) and world tokens are dropped where the
||| runtime doesn't need them; argument shapes follow the JS backend's jsPrim.
extPrim : String -> List String -> Maybe String
extPrim "prim__codegen" [] = Just (wlString "wolfram")
extPrim "prim__os" [] = Just (rt "osName[]")
extPrim "prim__newIORef" [_, v, _] = Just (rt "newIORef[" ++ v ++ "]")
extPrim "prim__readIORef" [_, r, _] = Just (rt "readIORef[" ++ r ++ "]")
extPrim "prim__writeIORef" [_, r, v, _] = Just (rt "writeIORef[" ++ r ++ ", " ++ v ++ "]")
extPrim "prim__newArray" [_, s, v, _] = Just (rt "newArray[" ++ s ++ ", " ++ v ++ "]")
extPrim "prim__arrayGet" [_, a, i, _] = Just (rt "arrayGet[" ++ a ++ ", " ++ i ++ "]")
extPrim "prim__arraySet" [_, a, i, v, _]
    = Just (rt "arraySet[" ++ a ++ ", " ++ i ++ ", " ++ v ++ "]")
extPrim "prim__getChar" [w] = Just (rt "getChar[" ++ w ++ "]")
extPrim _ _ = Nothing

-- Continuation-passing style (CPS) with closure conversion.
--
-- Every function and closure takes a continuation and every call is a tail
-- call, so deep (non-tail) Idris recursion builds continuation *values* on
-- the heap instead of growing WL's evaluation stack, which is capped by
-- $RecursionLimit and, past that, by the Windows C stack.
--
-- Closures (lambdas, thunks and continuations alike) are converted: the
-- code is lifted to a top-level definition taking its captured variables as
-- leading arguments, and the closure value is data, RT`Clo[code, captured...],
-- applied by the runtime rule Clo[f_, c___][a___] := f[c, a]. Runtime values
-- therefore never contain a Function with named variables. That matters:
-- WL implements With and Function application by substitution, renaming
-- clashing variables of nested scoping constructs, and self-similar chains
-- of Functions (CPS continuations; IO actions built by for_/traverse_) made
-- that cost proportional to the chain on every step, i.e. quadratic. Data
-- values are never walked.
--
--   top-level f, arity > 0   f[a_, b_, k_] := [[body]] k
--   zero-arity f (CAF)       f := f = [[body]] idK                 (a value)
--   closure \x => b          Clo[lamN, captured...];  lamN[captured..., x_, k_] := [[b]] k
--   continuation             Clo[contN, captured...]; contN[captured..., t_] := ...
--   closure call  e a b      e[a, Clo[contN, ...]]  (curried, one argument at a time)
--   thunk / force            Clo[lamN, captured...] with lamN[..., k_]  /  t[k]
--
-- The transform is one-pass with a meta-continuation (Danvy & Filinski):
-- Obj k is a WL continuation variable (we're in tail position: emit k[v]);
-- Meta m builds the rest of the code from a value, so no administrative
-- continuations are emitted. `reify` turns a Meta into a real continuation
-- only when one must be passed to a call.
--
-- Scope is tracked dynamically: every binder pushes its WL symbol on the
-- Scope stack while the code inside it is generated. Generation order
-- mirrors the nesting of the emitted code, so the stack is exactly what is
-- in scope at the point being emitted -- including when a Meta built
-- earlier runs inside a later binder. Lifting captures the in-scope symbols
-- its body mentions (a textual test, so it may over-capture, harmlessly).

||| Label for the definitions lifted out of expressions.
export
data LiftedDefs : Type where

||| Label for the stack of local symbols in scope.
export
data InScope : Type where

||| What to do with the value of the expression being translated.
data Cont = Obj String | Meta (String -> Core String)

||| The identity continuation, for CAFs and main.
idK : String
idK = rt "idK"

freshName : {auto f : Ref Fresh Int} -> String -> Core String
freshName p = pure $ genContext ++ p ++ show !fresh

||| Generate `act` with the WL symbols `names` in scope (temporaries: these
||| are fresh already).
bound : {auto s : Ref InScope (List (Maybe Name, String))} -> List String -> Core a -> Core a
bound names act = boundAll (map (\n => (Nothing, n)) names) act
  where
    boundAll : List (Maybe Name, String) -> Core a -> Core a
    boundAll entries act
        = do old <- get InScope
             put InScope (entries ++ old)
             r <- act
             put InScope old
             pure r

||| Generate `act` with Idris locals bound to the given WL symbols.
boundLocals : {auto s : Ref InScope (List (Maybe Name, String))} ->
              List (Name, String) -> Core a -> Core a
boundLocals locals act
    = do old <- get InScope
         put InScope (map (\(n, v) => (Just n, v)) locals ++ old)
         r <- act
         put InScope old
         pure r

||| A fresh WL symbol for a binder. Every binder gets its own, so no name is
||| ever shadowed: Idris's IR does reuse local names in nested scopes, and
||| once code is lifted into pattern-based definitions, a captured variable's
||| value would otherwise also replace an inner binder of the same name.
freshLocal : {auto f : Ref Fresh Int} -> Name -> Core String
freshLocal n = pure $ localSym n ++ "$" ++ show !fresh

||| The WL symbol an Idris local is currently bound to.
localRef : {auto s : Ref InScope (List (Maybe Name, String))} -> Name -> Core String
localRef n = pure $ fromMaybe (localSym n) (lookup (Just n) !(get InScope))

||| Does the WL symbol `v` occur in `code` as a whole symbol? A plain
||| substring test would also match `WolfdrisGen`k` inside `WolfdrisGen`k581`,
||| making closures capture (and keep alive) things they don't use.
occursSym : String -> String -> Bool
occursSym v code = go (unpack code)
  where
    symChar : Char -> Bool
    symChar c = isAlphaNum c || c == '$' || c == '`'

    vs : List Char
    vs = unpack v

    go : List Char -> Bool
    go [] = False
    go cs@(_ :: rest)
        = if isPrefixOf vs cs
             then case drop (length vs) cs of
                       (c :: _) => if symChar c then go rest else True
                       [] => True
             else go rest

||| Lift `body` (with parameters `params`, already generated) to a new
||| top-level definition taking the in-scope symbols it mentions first.
||| Returns the definition's name and those captured symbols.
liftDef : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
          {auto s : Ref InScope (List (Maybe Name, String))} ->
          String -> List String -> String -> Core (String, List String)
liftDef kind params body
    = do name <- freshName kind
         scope <- get InScope
         let caps = filter (\v => not (elem v params) && occursSym v body) (nub (map snd scope))
         update LiftedDefs ((name ++ "[" ++ commas (map (++ "_") (caps ++ params))
                             ++ "] := " ++ body ++ ";") ::)
         pure (name, caps)

||| Lift `body` and return a closure value for it.
lift : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
       {auto s : Ref InScope (List (Maybe Name, String))} ->
       String -> List String -> String -> Core String
lift kind params body
    = do (name, caps) <- liftDef kind params body
         pure $ rt "Clo[" ++ commas (name :: caps) ++ "]"

||| Bind `params` to `args` by lifting `body` and calling it directly. This
||| replaces With in generated code: With substitutes into its body, and a
||| body holding large values (lists, continuation chains, dictionaries)
||| that mention many distinct symbols gets walked in full on every With --
||| measured: linear in the value's size, so quadratic in loops. A
||| definition's pattern substitution only walks its own small template.
liftCall : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
           {auto s : Ref InScope (List (Maybe Name, String))} ->
           String -> List String -> List String -> String -> Core String
liftCall kind params args body
    = do (name, caps) <- liftDef kind params body
         pure $ name ++ "[" ++ commas (caps ++ args) ++ "]"

apply : Cont -> String -> Core String
apply (Obj k) v = pure $ k ++ "[" ++ v ++ "]"
apply (Meta m) v = m v

reify : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
        {auto s : Ref InScope (List (Maybe Name, String))} -> Cont -> Core String
reify (Obj k) = pure k
reify (Meta m)
    = do t <- freshName "t"
         body <- bound [t] (m t)
         lift "cont" [t] body

||| Branching needs a continuation every branch can share: bind a Meta to a
||| join point once rather than duplicating the rest of the code per branch.
withJoin : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
           {auto s : Ref InScope (List (Maybe Name, String))} ->
           Cont -> (Cont -> Core String) -> Core String
withJoin (Obj k) body = body (Obj k)
withJoin c body
    = do j <- freshName "j"
         k <- reify c
         inner <- bound [j] (body (Obj j))
         liftCall "join" [j] [k] inner

||| A value that is just a symbol can be used repeatedly as is.
isSymbol : String -> Bool
isSymbol = all (\c => isAlphaNum c || c == '$' || c == '`') . unpack

mutual
  cps : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
        {auto s : Ref InScope (List (Maybe Name, String))} -> NamedCExp -> Cont -> Core String
  cps (NmLocal _ n) c = apply c !(localRef n)
  cps (NmRef _ n) c = apply c (globalSym n)
  cps (NmLam _ x b) c
      = do k <- freshName "k"
           x' <- freshLocal x
           body <- boundLocals [(x, x')] (bound [k] (cps b (Obj k)))
           apply c !(lift "lam" [x', k] body)
  cps (NmLet _ x v b) c
      = cps v $ Meta $ \v' =>
          do x' <- freshLocal x
             body <- boundLocals [(x, x')] (cps b c)
             liftCall "let" [x'] [v'] body
  -- A zero-arity definition is a memoised value, referenced without [].
  cps (NmApp _ (NmRef _ n) []) c = apply c (globalSym n)
  cps (NmApp _ (NmRef _ n) args) c
      = cpsList args $ \vs =>
          pure $ globalSym n ++ "[" ++ commas (vs ++ [!(reify c)]) ++ "]"
  cps (NmApp _ fn args) c
      = cps fn $ Meta $ \fv => cpsList args $ \vs => applyClosure fv vs c
  cps (NmCon _ n _ tag args) c
      = cpsList args $ \vs => apply c (rt "Con[" ++ commas (tagLit n tag :: vs) ++ "]")
  cps (NmOp _ BelieveMe [_, _, x]) c = cps x c
  cps (NmOp _ Crash [_, msg]) c
      = cps msg $ Meta $ \m => pure $ rt "crash[" ++ m ++ "]"
  cps (NmOp _ op args) c
      = cpsList (toList args) $ \vs =>
          apply c (rt "op[" ++ commas (map wlString (opKeys op)) ++ "][" ++ commas vs ++ "]")
  -- Effectful (IORefs, arrays, getChar): evaluate now, so effects keep
  -- their order relative to later calls.
  cps (NmExtPrim _ p args) c
      = cpsList args $ \vs =>
          do let e = fromMaybe
                       (rt "crash[" ++ wlString ("extern not implemented: " ++ nameStr p) ++ "]")
                       (extPrim (nameStr (dropAllNS p)) vs)
             t <- freshName "t"
             body <- bound [t] (apply c t)
             -- the effect runs as the argument, before the body
             liftCall "eff" [t] [e] body
  cps (NmForce _ _ e) c
      = cps e $ Meta $ \t => pure $ t ++ "[" ++ !(reify c) ++ "]"
  cps (NmDelay _ _ e) c
      = do k <- freshName "k"
           body <- bound [k] (cps e (Obj k))
           apply c !(lift "lam" [k] body)
  cps (NmConCase _ sc alts def) c
      = cps sc $ Meta $ \sv => withJoin c $ \c' =>
          do s <- if isSymbol sv then pure sv else freshName "s"
             alts' <- bound [s] (traverse (conAlt s c') alts)
             def' <- bound [s] (defaultBranch def c')
             let sw = "Switch[" ++ s ++ "[[1]], " ++ commas (alts' ++ ["_, " ++ def']) ++ "]"
             if s == sv then pure sw else liftCall "case" [s] [sv] sw
  cps (NmConstCase _ sc alts def) c
      = cps sc $ Meta $ \sv => withJoin c $ \c' =>
          do alts' <- traverse (constAlt c') alts
             def' <- defaultBranch def c'
             pure $ "Switch[" ++ sv ++ ", " ++ commas (alts' ++ ["_, " ++ def']) ++ "]"
  cps (NmPrimVal _ v) c = apply c (constant v)
  cps (NmErased _) c = apply c (rt "erased")
  -- Compiler-generated crash: chez prints the bare message (no "ERROR: ").
  cps (NmCrash _ msg) _ = pure $ rt "crashRaw[" ++ wlString msg ++ "]"

  ||| Translate arguments left to right, then build from their values.
  cpsList : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
            {auto s : Ref InScope (List (Maybe Name, String))} ->
            List NamedCExp -> (List String -> Core String) -> Core String
  cpsList [] k = k []
  cpsList (e :: es) k = cps e $ Meta $ \v => cpsList es (\vs => k (v :: vs))

  ||| Closures take one argument (and a continuation) at a time.
  applyClosure : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
                 {auto s : Ref InScope (List (Maybe Name, String))} ->
                 String -> List String -> Cont -> Core String
  applyClosure fv [] c = apply c fv
  applyClosure fv [a] c = pure $ fv ++ "[" ++ a ++ ", " ++ !(reify c) ++ "]"
  applyClosure fv (a :: as) c
      = pure $ fv ++ "[" ++ a ++ ", " ++ !(reify (Meta $ \g => applyClosure g as c)) ++ "]"

  conAlt : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
           {auto s : Ref InScope (List (Maybe Name, String))} ->
           String -> Cont -> NamedConAlt -> Core String
  conAlt sc c (MkNConAlt n _ tag args body)
      = do names <- traverse freshLocal args
           body' <- boundLocals (zip args names) (cps body c)
           let fields = map (\i => sc ++ "[[" ++ show i ++ "]]") [2 .. S (length args)]
           branch <- if null args then pure body'
                                  else liftCall "alt" names (take (length args) fields) body'
           pure $ tagLit n tag ++ ", " ++ branch

  constAlt : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
             {auto s : Ref InScope (List (Maybe Name, String))} ->
             Cont -> NamedConstAlt -> Core String
  constAlt c (MkNConstAlt v body) = pure $ constant v ++ ", " ++ !(cps body c)

  defaultBranch : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
                  {auto s : Ref InScope (List (Maybe Name, String))} ->
                  Maybe NamedCExp -> Cont -> Core String
  defaultBranch (Just d) c = cps d c
  defaultBranch Nothing _ = pure $ rt "crashRaw[" ++ wlString "unmatched case" ++ "]"

||| The program's entry: run main with the identity continuation, under the
||| runtime's stack-overflow backstop.
export
emitMain : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
           {auto s : Ref InScope (List (Maybe Name, String))} -> NamedCExp -> Core String
emitMain e = pure $ rt "runMain[" ++ !(cps e (Obj idK)) ++ "]"

||| Foreign arguments that carry no value: the world token, and erased type
||| arguments (foreign definitions keep their implicits, e.g. `{0 a : Type}`).
noValue : CFType -> Bool
noValue CFWorld = True
noValue (CFUser (UN (Basic "Type")) []) = True
noValue _ = False

emitForeign : FC -> Name -> List String -> List CFType -> Core String
emitForeign fc n specs fargs
    = do -- Zip with fargs: [1 .. 0] is [1, 0] in Idris, not [].
         let xs = zipWith (\i, _ => genContext ++ "x" ++ show i) [1 .. length fargs] fargs
             k = genContext ++ "k"
         call <- case lookupForeign n of
           Just impl => pure $ impl ++ "[" ++ commas xs ++ "]"
           Nothing => case wolframSpec specs of
             Just fn => let args = map fst (filter (not . noValue . snd) (zip xs fargs)) in
                        pure $ fn ++ "[" ++ commas args ++ "]"
             Nothing => throw $ GenericMsg fc $
               "Wolfdris: no Wolfram implementation for foreign function "
               ++ nameStr n ++ ". Its specs: " ++ show specs
         -- Foreign implementations are direct style; hand the result to k.
         -- Zero-arity ones are values, referenced without [].
         pure $ if null fargs
                   then globalSym n ++ " := " ++ call
                   else globalSym n ++ "[" ++ commas (map (++ "_") (xs ++ [k])) ++ "] := "
                        ++ k ++ "[" ++ call ++ "]"

||| One top-level definition. Constructors need no code. Definitions lifted
||| out of its expressions accumulate in the LiftedDefs ref.
export
emitDef : {auto f : Ref Fresh Int} -> {auto l : Ref LiftedDefs (List String)} ->
          {auto s : Ref InScope (List (Maybe Name, String))} -> (Name, FC, NamedDef) -> Core String
-- A top-level Lazy constant: memoise its forced value, as chez's
-- (define f (delay ...)) does, so forcing it twice doesn't recompute.
emitDef (n, _, MkNmFun [] (NmDelay _ _ body))
    = let val = globalSym n ++ "$lazy"
          k = genContext ++ "k" in
      pure $ val ++ " := " ++ val ++ " = " ++ !(cps body (Obj idK)) ++ ";\n"
             ++ globalSym n ++ " := " ++ globalSym n
             ++ " = Function[{" ++ k ++ "}, " ++ k ++ "[" ++ val ++ "]];"
-- Computed once, on first use, with the identity continuation.
emitDef (n, _, MkNmFun [] body)
    = pure $ globalSym n ++ " := " ++ globalSym n ++ " = " ++ !(cps body (Obj idK)) ++ ";"
emitDef (n, _, MkNmFun args body)
    = let k = genContext ++ "k"
          args' = map localSym args in
      pure $ globalSym n ++ "[" ++ commas (map (++ "_") (args' ++ [k]))
             ++ "] := " ++ !(boundLocals (zip args args') (bound [k] (cps body (Obj k)))) ++ ";"
emitDef (n, _, MkNmCon _ _ _) = pure ""
emitDef (n, fc, MkNmForeign specs fargs _) = pure $ !(emitForeign fc n specs fargs) ++ ";"
-- Fails when used, whether referenced bare (zero arity) or applied.
emitDef (n, _, MkNmError e) = pure $ globalSym n ++ " := " ++ !(cps e (Obj idK)) ++ ";"
