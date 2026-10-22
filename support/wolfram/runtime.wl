(* ==== Wolfdris runtime ==== *)
(* Inlined into every generated program by the Wolfdris compiler.
   Semantics follow the Idris 2 chez backend (support/chez/support.ss and
   src/Compiler/Scheme/Common.idr in Idris 2 v0.8.0). *)

$HistoryLength = 0;
(* Tail calls in If/With/Switch/Function count against $IterationLimit
   instead of growing the stack, so it must be unlimited. *)
$IterationLimit = Infinity;
(* Without this, wolframscript prints non-ASCII as \[Name] escapes. *)
SetOptions[$Output, CharacterEncoding -> "UTF-8"];

Begin["WolfdrisRT`"];

(* ---- Values ---- *)
(* Con[tag, fields...] is a constructor value; Con has no definitions, so
   it stays inert. *)
unit = Con[0];

crash[msg_String] := (
  WriteString[Streams["stderr"], "ERROR: " <> msg <> "\n"];
  Exit[1]);
crash[msg_] := crash[ToString[msg]];

(* ---- Integer types ---- *)
signedBits = <|"Int" -> 64, "Int8" -> 8, "Int16" -> 16, "Int32" -> 32, "Int64" -> 64|>;
unsignedBits = <|"Bits8" -> 8, "Bits16" -> 16, "Bits32" -> 32, "Bits64" -> 64|>;
intTypes = Join[{"Integer"}, Keys[signedBits], Keys[unsignedBits]];

wrapS[n_][x_] := Mod[x + 2^(n - 1), 2^n] - 2^(n - 1);
wrapU[n_][x_] := Mod[x, 2^n];
wrap["Integer"] = Identity;
KeyValueMap[(wrap[#1] = wrapS[#2]) &, signedBits];
KeyValueMap[(wrap[#1] = wrapU[#2]) &, unsignedBits];

(* Euclidean division: the remainder is always >= 0. *)
euclidMod[a_, b_] := Mod[a, Abs[b]];
euclidDiv[a_, b_] := (a - Mod[a, Abs[b]])/b;

divByZero[] := crash["division by zero"];

Do[With[{t = t, w = wrap[t]},
    op["Add", t][a_, b_] := w[a + b];
    op["Sub", t][a_, b_] := w[a - b];
    op["Mul", t][a_, b_] := w[a b];
    (* chez does not wrap Neg *)
    op["Neg", t][a_] := -a;
    op["Mod", t][a_, b_] := If[b == 0, divByZero[], euclidMod[a, b]]],
  {t, intTypes}];

Do[With[{t = t, w = wrap[t]},
    op["Div", t][a_, b_] := If[b == 0, divByZero[], w[euclidDiv[a, b]]]],
  {t, Join[{"Integer"}, Keys[signedBits]]}];

Do[With[{t = t},
    op["Div", t][a_, b_] := If[b == 0, divByZero[], Quotient[a, b]]],
  {t, Keys[unsignedBits]}];

(* ---- Comparisons (return Int 0/1) ---- *)
Do[With[{t = t},
    op["LT", t][a_, b_] := Boole[a < b];
    op["LTE", t][a_, b_] := Boole[a <= b];
    op["EQ", t][a_, b_] := Boole[a == b];
    op["GTE", t][a_, b_] := Boole[a >= b];
    op["GT", t][a_, b_] := Boole[a > b]],
  {t, Join[intTypes, {"Char", "Double"}]}];

(* Strings compare by code point, like chez's string<? *)
strCmp[a_String, b_String] := Module[{x = ToCharacterCode[a], y = ToCharacterCode[b], i},
  i = SelectFirst[Range[Min[Length[x], Length[y]]], x[[#]] =!= y[[#]] &, None];
  If[i === None, Sign[Length[x] - Length[y]], Sign[x[[i]] - y[[i]]]]];

op["LT", "String"][a_, b_] := Boole[strCmp[a, b] < 0];
op["LTE", "String"][a_, b_] := Boole[strCmp[a, b] <= 0];
op["EQ", "String"][a_, b_] := Boole[a === b];
op["GTE", "String"][a_, b_] := Boole[strCmp[a, b] >= 0];
op["GT", "String"][a_, b_] := Boole[strCmp[a, b] > 0];

(* ---- Strings (Char is an integer code point) ---- *)
op["StrLength"][s_] := StringLength[s];
op["StrHead"][s_] := If[s === "", crash["strHead: empty string"],
  First[ToCharacterCode[StringTake[s, 1]]]];
op["StrTail"][s_] := If[s === "", crash["strTail: empty string"], StringDrop[s, 1]];
op["StrIndex"][s_, i_] := If[0 <= i < StringLength[s],
  First[ToCharacterCode[StringTake[s, {i + 1}]]],
  crash["strIndex: index out of range"]];
op["StrCons"][c_, s_] := FromCharacterCode[c] <> s;
op["StrAppend"][a_, b_] := a <> b;
op["StrReverse"][s_] := StringReverse[s];
(* chez string-substr: clamps offset and length *)
op["StrSubstr"][off_, len_, s_] := With[{l = StringLength[s], b = Max[0, off]},
  If[b > l, "", StringTake[s, {b + 1, Min[l, b + Max[0, len]]}]]];

(* ---- Casts ---- *)
intString[x_Integer] := If[x < 0, "-" <> IntegerString[-x], IntegerString[x]];

(* chez cast-string-int: parse a number (truncated), 0 if it isn't one. *)
parseNumber[s_String] := Which[
  StringMatchQ[s, RegularExpression["[+-]?[0-9]+"]], ToExpression[s],
  StringMatchQ[s, RegularExpression["[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?"]],
    ToExpression[StringReplace[s, {"e" -> "*^", "E" -> "*^"}]],
  True, 0];

validChar[c_] := 0 <= c <= 16^^d7ff || 16^^e000 <= c <= 16^^10ffff;

Do[With[{from = from, to = to, w = wrap[to]},
    op["Cast", from, to][x_] := w[x]],
  {from, intTypes}, {to, intTypes}];

Do[With[{t = t, w = wrap[t]},
    op["Cast", t, "String"][x_] := intString[x];
    op["Cast", "String", t][s_] := w[IntegerPart[parseNumber[s]]];
    op["Cast", "Char", t][c_] := w[c];
    op["Cast", t, "Char"][x_] := If[validChar[x], x, 0];
    op["Cast", t, "Double"][x_] := N[x];
    op["Cast", "Double", t][x_] := w[IntegerPart[x]]],
  {t, intTypes}];

op["Cast", "Char", "String"][c_] := FromCharacterCode[c];

(* ---- Double ---- *)
(* Step 1: IEEE special values are inert symbols; Double ops other than the
   comparisons and int casts fall through to "not implemented". *)
dNaN; dInf; dNegInf;

(* ---- Anything else ---- *)
op[keys__][___] := crash["not implemented: " <> StringRiffle[{keys}, " "]];

(* ---- Foreign functions (see src/Wolfdris/Foreign.idr) ---- *)
putStr[s_, _] := (WriteString[$Output, s]; unit);
putChar[c_, _] := (WriteString[$Output, FromCharacterCode[c]]; unit);
getStr[_] := crash["getLine is not implemented yet"];

(* Idris List <-> WL list, iteratively so long lists don't hit the
   recursion limit. Nil is Con[0], cons is Con[1, head, tail]. *)
conToList[l_] := Module[{x = l},
  Join @@ Reap[While[x[[1]] === 1, Sow[x[[2]]]; x = x[[3]]]][[2]]];
listToCon[xs_List] := Fold[Con[1, #2, #1] &, Con[0], Reverse[xs]];

fastPack[l_] := FromCharacterCode[conToList[l]];
fastUnpack[s_] := listToCon[ToCharacterCode[s]];
fastConcat[l_] := StringJoin[conToList[l]];

End[];
