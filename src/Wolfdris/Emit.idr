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

mutual
  export
  emit : {auto f : Ref Fresh Int} -> NamedCExp -> Core String
  emit (NmLocal _ n) = pure (localSym n)
  emit (NmRef _ n) = pure (globalSym n)
  emit (NmLam _ x b) = pure $ "Function[{" ++ localSym x ++ "}, " ++ !(emit b) ++ "]"
  emit (NmLet _ x v b)
      = pure $ "With[{" ++ localSym x ++ " = " ++ !(emit v) ++ "}, " ++ !(emit b) ++ "]"
  -- A zero-arity definition is a memoised constant, referenced without [].
  emit (NmApp _ (NmRef _ n) []) = pure (globalSym n)
  emit (NmApp _ (NmRef _ n) args)
      = pure $ globalSym n ++ "[" ++ commas !(traverse emit args) ++ "]"
  -- Closures take one argument at a time.
  emit (NmApp _ fn args)
      = do fn' <- emit fn
           args' <- traverse emit args
           pure $ foldl (\acc, a => acc ++ "[" ++ a ++ "]") fn' args'
  emit (NmCon _ n _ tag args)
      = pure $ rt "Con[" ++ commas (tagLit n tag :: !(traverse emit args)) ++ "]"
  emit (NmOp _ BelieveMe [_, _, x]) = emit x
  emit (NmOp _ Crash [_, msg]) = pure $ rt "crash[" ++ !(emit msg) ++ "]"
  emit (NmOp _ op args)
      = pure $ rt "op[" ++ commas (map wlString (opKeys op)) ++ "]["
               ++ commas !(traverse emit (toList args)) ++ "]"
  emit (NmExtPrim _ p args)
      = do args' <- traverse emit args
           pure $ fromMaybe
             (rt "crash[" ++ wlString ("extern not implemented: " ++ nameStr p) ++ "]")
             (extPrim (nameStr (dropAllNS p)) args')
  emit (NmForce _ _ e) = pure $ !(emit e) ++ "[]"
  emit (NmDelay _ _ e) = pure $ "Function[{}, " ++ !(emit e) ++ "]"
  emit (NmConCase _ sc alts def)
      = do (bind, s) <- scrutinee sc
           alts' <- traverse (conAlt s) alts
           def' <- defaultBranch def
           let sw = "Switch[" ++ s ++ "[[1]], " ++ commas (alts' ++ ["_, " ++ def']) ++ "]"
           pure $ maybe sw (\v => "With[{" ++ s ++ " = " ++ v ++ "}, " ++ sw ++ "]") bind
  emit (NmConstCase _ sc alts def)
      = do sc' <- emit sc
           alts' <- traverse constAlt alts
           def' <- defaultBranch def
           pure $ "Switch[" ++ sc' ++ ", " ++ commas (alts' ++ ["_, " ++ def']) ++ "]"
  emit (NmPrimVal _ c) = pure (constant c)
  emit (NmErased _) = pure (rt "erased")
  emit (NmCrash _ msg) = pure $ rt "crash[" ++ wlString msg ++ "]"

  ||| A local scrutinee is used directly; anything else is bound once.
  scrutinee : {auto f : Ref Fresh Int} -> NamedCExp -> Core (Maybe String, String)
  scrutinee (NmLocal _ n) = pure (Nothing, localSym n)
  scrutinee sc = do i <- fresh
                    pure (Just !(emit sc), scrutSym i)

  conAlt : {auto f : Ref Fresh Int} -> String -> NamedConAlt -> Core String
  conAlt s (MkNConAlt n _ tag args body)
      = do body' <- emit body
           let fields = zipWith (\a, i => localSym a ++ " = " ++ s ++ "[[" ++ show i ++ "]]")
                                args [2 .. S (length args)]
           pure $ tagLit n tag ++ ", "
                  ++ (if null args then body'
                                   else "With[{" ++ commas fields ++ "}, " ++ body' ++ "]")

  constAlt : {auto f : Ref Fresh Int} -> NamedConstAlt -> Core String
  constAlt (MkNConstAlt c body) = pure $ constant c ++ ", " ++ !(emit body)

  defaultBranch : {auto f : Ref Fresh Int} -> Maybe NamedCExp -> Core String
  defaultBranch (Just d) = emit d
  defaultBranch Nothing = pure $ rt "crash[" ++ wlString "unmatched case" ++ "]"

isWorld : CFType -> Bool
isWorld CFWorld = True
isWorld _ = False

emitForeign : FC -> Name -> List String -> List CFType -> Core String
emitForeign fc n specs fargs
    = do -- Zip with fargs: [1 .. 0] is [1, 0] in Idris, not [].
         let xs = zipWith (\i, _ => genContext ++ "x" ++ show i) [1 .. length fargs] fargs
             -- Zero-arity definitions are referenced without [], see emit.
             lhs = if null fargs
                      then globalSym n ++ " := "
                      else globalSym n ++ "[" ++ commas (map (++ "_") xs) ++ "] := "
         case lookupForeign n of
              Just impl => pure $ lhs ++ impl ++ "[" ++ commas xs ++ "]"
              Nothing => case wolframSpec specs of
                Just fn => let args = map fst (filter (not . isWorld . snd) (zip xs fargs)) in
                           pure $ lhs ++ fn ++ "[" ++ commas args ++ "]"
                Nothing => throw $ GenericMsg fc $
                  "Wolfdris: no Wolfram implementation for foreign function "
                  ++ nameStr n ++ ". Its specs: " ++ show specs

||| One top-level definition. Constructors need no code.
export
emitDef : {auto f : Ref Fresh Int} -> (Name, FC, NamedDef) -> Core String
emitDef (n, _, MkNmFun [] body)
    = pure $ globalSym n ++ " := " ++ globalSym n ++ " = " ++ !(emit body) ++ ";"
emitDef (n, _, MkNmFun args body)
    = pure $ globalSym n ++ "[" ++ commas (map (\a => localSym a ++ "_") args)
             ++ "] := " ++ !(emit body) ++ ";"
emitDef (n, _, MkNmCon _ _ _) = pure ""
emitDef (n, fc, MkNmForeign specs fargs _) = pure $ !(emitForeign fc n specs fargs) ++ ";"
emitDef (n, _, MkNmError e) = pure $ globalSym n ++ "[___] := " ++ !(emit e) ++ ";"
