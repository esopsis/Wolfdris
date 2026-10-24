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
(* With only System` on the path, every name below is created in
   WolfdrisRT`. Otherwise a name that already exists elsewhere on the path
   (say a user's Global`op) would be picked up and redefined. *)
WolfdrisRT`$savedContextPath = $ContextPath;
$ContextPath = {"System`"};

(* ---- Values ---- *)
(* Con[tag, fields...] is a constructor value; Con has no definitions, so
   it stays inert. *)
unit = Con[0];

(* Like chez's blodwen-error-quit: the message on stdout, then exit 1.
   crashRaw is for compiler-generated crashes (NmCrash: impossible cases,
   holes); crash is idris_crash, which chez prefixes with "ERROR: ". *)
crashRaw[msg_String] := (WriteString[$Output, msg <> "\n"]; Exit[1]);
crashRaw[msg_] := crashRaw[ToString[msg]];
crash[msg_String] := crashRaw["ERROR: " <> msg];
crash[msg_] := crash[ToString[msg]];

(* ---- Continuations and the entry point ---- *)
(* Generated code is in continuation-passing style (see Emit.idr): every
   call is a tail call, so Idris recursion depth doesn't grow WL's stack. *)
idK = Function[{v}, v];

(* Closures and continuations are data: Clo[code, captured...], where code is
   a lifted top-level definition taking the captured values first (see the
   CPS notes in Emit.idr for why not Function). Applying one is a tail call. *)
Clo[f_, c___][a___] := f[c, a];

(* Backstop for anything that still nests too deeply. Hitting
   $RecursionLimit doesn't stop evaluation on its own: TerminatedEvaluation
   comes back as a value and the program carries on with garbage. So a
   message handler aborts, and runMain turns that into a clean crash.
   (Exit doesn't work from inside the handler under wolframscript.) 10000
   is about half the largest limit measured to fail cleanly for every code
   shape tried; past ~40000 some shapes overflow the C stack and the kernel
   dies instead. *)
$RecursionLimit = 10000;
overflowed = False;
overflowHandler[Hold[Message[$RecursionLimit::reclim | $RecursionLimit::reclim2, ___], _]] :=
  (overflowed = True; Abort[]);
Internal`AddHandler["Message", overflowHandler];
(* WL's own messages would end up in the program's output (wolframscript
   merges stderr into stdout); set WOLFDRIS_DEBUG to see them. *)
If[!StringQ[Environment["WOLFDRIS_DEBUG"]], $Messages = {}];

(* WOLFDRIS_TIMEOUT (seconds) is enforced here, inside the kernel: killing
   wolframscript from WSL (e.g. with `timeout`) leaves the Windows kernel
   running. *)
timeLimit[] := With[{t = Environment["WOLFDRIS_TIMEOUT"]},
  If[StringQ[t] && StringMatchQ[t, DigitCharacter ..], FromDigits[t], Infinity]];

SetAttributes[runMain, HoldAll];
runMain[main_] := CheckAbort[
  TimeConstrained[main;, timeLimit[], crash["time limit exceeded"]],
  If[overflowed, crash["stack overflow (recursion too deep)"], crashRaw["aborted"]]];

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

(* chez: ShiftL wraps for bounded types; ShiftR is an arithmetic shift and
   the bitwise ops act on the (two's complement) value, none of them wrap. *)
Do[With[{t = t, w = wrap[t]},
    op["ShiftL", t][a_, b_] := w[BitShiftLeft[a, b]];
    (* Floor, not BitShiftRight: BitShiftRight[-1, 3] is 0, chez's ash gives -1 *)
    op["ShiftR", t][a_, b_] := Floor[a / 2^b];
    op["BAnd", t][a_, b_] := BitAnd[a, b];
    op["BOr", t][a_, b_] := BitOr[a, b];
    op["BXOr", t][a_, b_] := BitXor[a, b]],
  {t, intTypes}];

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
  {t, Join[intTypes, {"Char"}]}];

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

(* The exact rational value of a decimal string like "-12.5e-3", or None
   if it isn't one. *)
decimalRegex = RegularExpression["([+-]?)([0-9]*)\\.?([0-9]*)(?:[eE]([+-]?[0-9]+))?"];
exactDecimal[s_String] := If[
  !StringMatchQ[s, decimalRegex] || !StringContainsQ[s, DigitCharacter] ||
    StringMatchQ[s, RegularExpression["[+-]?\\.?[eE].*"]],
  None,
  First[StringCases[s, decimalRegex :>
    If["$1" === "-", -1, 1] *
      FromDigits["$2" <> "$3"] / 10^StringLength["$3"] *
      10^If["$4" === "", 0, ToExpression["$4"]]]]];

(* chez cast-string-int: parse a number (truncated), 0 if it isn't one. *)
parseNumber[s_String] := Replace[exactDecimal[s], None -> 0];

validChar[c_] := 0 <= c <= 16^^d7ff || 16^^e000 <= c <= 16^^10ffff;

Do[With[{from = from, to = to, w = wrap[to]},
    op["Cast", from, to][x_] := w[x]],
  {from, intTypes}, {to, intTypes}];

Do[With[{t = t, w = wrap[t]},
    op["Cast", t, "String"][x_] := intString[x];
    op["Cast", "String", t][s_] := w[IntegerPart[parseNumber[s]]];
    op["Cast", "Char", t][c_] := w[c];
    op["Cast", t, "Char"][x_] := If[validChar[x], x, 0];
    op["Cast", t, "Double"][x_] := toDouble[x];
    op["Cast", "Double", t][x_] := If[nanQ[x] || infQ[x],
      crash["cast: Double is not finite"], w[IntegerPart[ex[x]]]]],
  {t, intTypes}];

op["Cast", "Char", "String"][c_] := FromCharacterCode[c];

(* ---- Double ---- *)
(* A Double is a machine real, or Infinity, -Infinity, or Indeterminate for
   NaN. WL doesn't do IEEE overflow, NaN or rounding on its own (e.g.
   1.*^308 * 10. is a bignum, 2.^1024. comes out finite), so every result
   goes through toDouble. Comparisons use exact values: WL's Equal and Less
   have a tolerance for machine reals. There is no signed zero. *)
nanQ[x_] := x === Indeterminate;
infQ[x_] := x === Infinity || x === -Infinity;
ex[x_Real] := SetPrecision[x, Infinity];
ex[x_] := x;

(* Exact rational -> nearest double, ties to even. Don't use N[r]: it is not
   correctly rounded (it disagreed with chez's exact->inexact on 558 of 3000
   random rationals; this agreed on all). Normal results are built as
   (m 2^-52) * 2^e2, which is exact in machine arithmetic. Subnormals use
   SetPrecision of the exactly representable value, which was bit-exact for
   all 2022 tested; ImportByteArray gets every subnormal wrong. *)
fromExact[r_] := Module[{a = Abs[r], e2, m},
  Which[
    a == 0, 0.,
    (* k == 2^52 correctly rolls into the smallest normal *)
    a < 2^-1022, Sign[r] Quiet[SetPrecision[Round[a 2^1074] 2^-1074, MachinePrecision]],
    True,
      (* e2 = Floor[Log2[a]], from bit lengths (exact Log is slow) *)
      e2 = BitLength[Numerator[a]] - BitLength[Denominator[a]];
      If[a < 2^e2, e2--];
      m = Round[a 2^(52 - e2)];
      If[m == 2^53, m = 2^52; e2++];
      If[e2 + 1023 >= 2047, Sign[r] Infinity,
        Sign[r] (N[m] * 2.^-52) * 2.^e2]]];

toDouble[r_] := Which[
  Head[r] === Real && MachineNumberQ[r], r,
  infQ[r] || nanQ[r], r,
  MatchQ[r, _Integer | _Rational], fromExact[r],
  Head[r] === Real, fromExact[SetPrecision[r, Infinity]],
  Head[r] === Overflow, Infinity,
  Head[r] === Underflow, 0.,
  True, Indeterminate];  (* ComplexInfinity, Complex, other directions *)

op["Add", "Double"][a_, b_] := toDouble[Quiet[a + b]];
op["Sub", "Double"][a_, b_] := toDouble[Quiet[a - b]];
op["Mul", "Double"][a_, b_] := toDouble[Quiet[a b]];
op["Div", "Double"][a_, b_] := Which[
  nanQ[a] || nanQ[b], Indeterminate,
  ex[b] == 0, If[ex[a] == 0, Indeterminate, Sign[a] Infinity],
  True, toDouble[Quiet[a / b]]];
op["Neg", "Double"][a_] := toDouble[-a];

Do[With[{o = First[p], f = Last[p]},
    op[o, "Double"][a_, b_] := If[nanQ[a] || nanQ[b], 0, Boole[f[ex[a], ex[b]]]]],
  {p, {{"LT", Less}, {"LTE", LessEqual}, {"EQ", Equal}, {"GTE", GreaterEqual}, {"GT", Greater}}}];

(* Unary math: IEEE results for special inputs, then compute and convert. *)
op["DoubleExp"][a_] := Which[nanQ[a] || a === Infinity, a, a === -Infinity, 0.,
  True, toDouble[Quiet[Exp[a]]]];
op["DoubleLog"][a_] := Which[nanQ[a] || a === Infinity, a, a === -Infinity, Indeterminate,
  ex[a] < 0, Indeterminate, ex[a] == 0, -Infinity, True, toDouble[Quiet[Log[a]]]];
op["DoubleSqrt"][a_] := Which[nanQ[a] || a === Infinity, a, a === -Infinity, Indeterminate,
  ex[a] < 0, Indeterminate, True, toDouble[Quiet[Sqrt[a]]]];
Do[With[{o = First[p], f = Last[p]},
    op[o][a_] := If[nanQ[a] || infQ[a], Indeterminate, toDouble[Quiet[f[a]]]]],
  {p, {{"DoubleSin", Sin}, {"DoubleCos", Cos}, {"DoubleTan", Tan}}}];
Do[With[{o = First[p], f = Last[p]},
    op[o][a_] := If[nanQ[a] || infQ[a] || Abs[ex[a]] > 1, Indeterminate,
      toDouble[Quiet[f[a]]]]],
  {p, {{"DoubleASin", ArcSin}, {"DoubleACos", ArcCos}}}];
op["DoubleATan"][a_] := Which[nanQ[a], a, a === Infinity, N[Pi/2], a === -Infinity, -N[Pi/2],
  True, toDouble[Quiet[ArcTan[a]]]];
op["DoubleFloor"][a_] := If[nanQ[a] || infQ[a], a, toDouble[Floor[ex[a]]]];
op["DoubleCeiling"][a_] := If[nanQ[a] || infQ[a], a, toDouble[Ceiling[ex[a]]]];

(* pow, following the C99/IEEE special cases. Finite results are computed
   at 40 digits and rounded: machine Power gets overflow wrong. *)
intValuedQ[x_] := Head[x] === Real && FractionalPart[ex[x]] == 0;
op["DoublePow"][a_, b_] := Which[
  !nanQ[b] && ex[b] == 0, 1.,
  !nanQ[a] && ex[a] == 1, 1.,
  nanQ[a] || nanQ[b], Indeterminate,
  b === Infinity, Which[Abs[ex[a]] > 1, Infinity, Abs[ex[a]] < 1, 0., True, 1.],
  b === -Infinity, Which[Abs[ex[a]] < 1, Infinity, Abs[ex[a]] > 1, 0., True, 1.],
  a === Infinity, If[ex[b] < 0, 0., Infinity],
  a === -Infinity, Which[ex[b] < 0, 0., intValuedQ[b] && OddQ[Round[ex[b]]], -Infinity,
    True, Infinity],
  ex[a] == 0, If[ex[b] < 0, Infinity, 0.],
  intValuedQ[b], toDouble[Quiet[SetPrecision[a, 40]^Round[ex[b]]]],
  ex[a] < 0, Indeterminate,
  True, toDouble[Quiet[SetPrecision[a, 40]^SetPrecision[b, 40]]]];

(* chez number->string for flonums: the shortest digits that round-trip;
   plain notation when 1e-3 <= |x| < 1e10, otherwise d.ddde<n>;
   subnormals get chez's "|<bits of precision>" suffix. *)
showDouble[x_] := Which[
  x === Infinity, "+inf.0",
  x === -Infinity, "-inf.0",
  nanQ[x], "+nan.0",
  ex[x] == 0, "0.0",
  True, If[ex[x] < 0, "-", ""] <> showPositive[Abs[ex[x]]]];

showPositive[a_] := Module[{e, n = 1, m, ds, k, ee, d, s},
  e = RealDigits[a, 10, 1][[2]];  (* a = 0.d... * 10^e *)
  While[n < 17 && ex[fromExact[Round[a 10^(n - e)] 10^(e - n)]] != a, n++];
  m = Round[a 10^(n - e)];
  ds = IntegerDigits[m];
  ee = Length[ds] + e - n;        (* now a ~ 0.ds * 10^ee *)
  ds = Drop[ds, -LengthWhile[Reverse[ds], # == 0 &]];
  k = Length[ds];
  d = StringJoin[ToString /@ ds];
  s = Which[
    -2 <= ee <= 0, "0." <> StringRepeat["0", -ee] <> d,
    1 <= ee <= 10 && ee >= k, d <> StringRepeat["0", ee - k] <> ".0",
    1 <= ee <= 10, StringTake[d, ee] <> "." <> StringDrop[d, ee],
    True, StringTake[d, 1] <> If[k > 1, "." <> StringDrop[d, 1], ""] <>
      "e" <> intString[ee - 1]];
  If[a < 2^-1022, s <> "|" <> ToString[BitLength[a 2^1074]], s]];

(* chez cast-string-double *)
parseDouble[s_String] := Switch[s,
  "+inf.0", Infinity,
  "-inf.0", -Infinity,
  "+nan.0" | "-nan.0", Indeterminate,
  _, Replace[exactDecimal[s], {None -> 0., r_ :> toDouble[r]}]];

op["Cast", "Double", "String"][x_] := showDouble[x];
op["Cast", "String", "Double"][s_] := parseDouble[s];

(* Data.Double constants (zero-argument foreigns) *)
doubleNaN[] := Indeterminate;
doubleInf[] := Infinity;
doubleEpsilon[] := $MachineEpsilon;
doubleUnitRoundoff[] := $MachineEpsilon/2;

(* ---- Anything else ---- *)
op[keys__][___] := crash["not implemented: " <> StringRiffle[{keys}, " "]];

(* ---- Foreign functions (see src/Wolfdris/Foreign.idr) ---- *)
putStr[s_, _] := (WriteString[$Output, s]; unit);
putChar[c_, _] := (WriteString[$Output, FromCharacterCode[c]]; unit);

(* ---- Pointers and errno ---- *)
(* A Ptr String is the string itself; NULL is the symbol nullPtr. *)
isNullPtr[p_] := Boole[p === nullPtr];
nullPtrConst[] := nullPtr;
getString[p_] := p;
freePtr[_, _] := unit;

lastErrno = 0;
setErrno[e_] := (lastErrno = e);
getErrno[_] := lastErrno;
strerrors = <|0 -> "Success", 1 -> "Operation not permitted", 2 -> "No such file or directory",
  13 -> "Permission denied", 17 -> "File exists", 20 -> "Not a directory",
  21 -> "Is a directory", 39 -> "Directory not empty"|>;
strerror[e_, _] := Lookup[strerrors, e, "Unknown error " <> intString[e]];

(* ---- Files ---- *)
(* Handles are inert FileH[h]. Files opened for reading are loaded whole into
   fbuf[h] and read with C stdio semantics (fpos[h] is the next character;
   feofFlag[h] is only set once a read hits the end). Handles 0, 1, 2 are
   stdin, stdout, stderr. *)

(* wolframscript gives -file scripts no readable stdin stream: all of stdin
   arrives up front in $ScriptInputString, as raw UTF-8 bytes one per
   character. So interactive (prompt-then-read) programs aren't possible. *)
stdinBuf := stdinBuf = If[StringQ[$ScriptInputString],
  With[{bytes = ToCharacterCode[$ScriptInputString]},
    If[bytes === {} || Max[bytes] < 256,
      Quiet[FromCharacterCode[bytes, "UTF-8"]], $ScriptInputString]],
  ""];
fbuf[0] := fbuf[0] = stdinBuf;
fpos[0] = 1;
fileCount = 2;

atEnd[h_] := fpos[h] > StringLength[fbuf[h]];

(* getline: up to and including the next "\n"; "" at end of input *)
readLineH[h_] := Module[{b = fbuf[h], p = fpos[h], rest, nl},
  If[atEnd[h], feofFlag[h] = True; "",
    rest = StringDrop[b, p - 1];
    nl = StringPosition[rest, "\n", 1];
    If[nl === {},
      fpos[h] = StringLength[b] + 1; feofFlag[h] = True; rest,
      fpos[h] = p + nl[[1, 1]]; StringTake[rest, nl[[1, 1]]]]]];
(* fread: up to n characters; NULL if none *)
readCharsH[n_, h_] := Module[{k},
  If[atEnd[h], feofFlag[h] = True; nullPtr,
    k = Min[n, StringLength[fbuf[h]] - fpos[h] + 1];
    If[k < n, feofFlag[h] = True];
    fpos[h] += k;
    StringTake[fbuf[h], {fpos[h] - k, fpos[h] - 1}]]];
(* fgetc: a code point, or -1 at end *)
readCharH[h_] := If[atEnd[h], feofFlag[h] = True; -1,
  fpos[h]++; First[ToCharacterCode[StringTake[fbuf[h], {fpos[h] - 1}]]]];

(* idris2_getStr: the next line without its "\n" *)
getStr[_] := StringDelete[readLineH[0], "\n" ~~ EndOfString];
getChar[_] := Max[readCharH[0], 0];

readFileUTF8[name_] := With[{bytes = Quiet[ReadByteArray[name]]},
  Which[bytes === EndOfFile, "",
        Head[bytes] === ByteArray, FromCharacterCode[Normal[bytes], "UTF-8"],
        True, $Failed]];

openFile[name_, mode_, _] := Module[{m = StringDelete[mode, "b"], h, s},
  Which[
    StringStartsQ[m, "r"],
      Which[
        DirectoryQ[name], setErrno[21]; nullPtr,
        !FileExistsQ[name], setErrno[2]; nullPtr,
        True, s = readFileUTF8[name];
          If[s === $Failed, setErrno[13]; nullPtr,
            h = ++fileCount; fbuf[h] = s; fpos[h] = 1; fname[h] = name; FileH[h]]],
    StringStartsQ[m, "w" | "a"],
      If[!DirectoryQ[DirectoryName[ExpandFileName[name]]], setErrno[2]; nullPtr,
        s = Quiet[If[StringStartsQ[m, "a"], OpenAppend, OpenWrite][name, BinaryFormat -> True]];
        If[Head[s] =!= OutputStream, setErrno[13]; nullPtr,
          h = ++fileCount; fstream[h] = s; fname[h] = name; FileH[h]]],
    True, setErrno[22]; nullPtr]];

closeFile[FileH[h_], _] := (If[Head[fstream[h]] === OutputStream, Close[fstream[h]]]; unit);

writeLine[FileH[1], s_, _] := (WriteString[$Output, s]; 1);
(* wolframscript merges the kernel's stderr into stdout anyway *)
writeLine[FileH[2], s_, _] := (WriteString[Streams["stderr"], s]; 1);
writeLine[FileH[h_], s_, _] := If[Head[fstream[h]] === OutputStream,
  BinaryWrite[fstream[h], ToCharacterCode[s, "UTF-8"]]; 1, 0];

readLine[FileH[h_], _] := readLineH[h];
readChars[n_, FileH[h_], _] := readCharsH[n, h];
readChar[FileH[h_], _] := readCharH[h];
seekLine[FileH[h_], _] := (readLineH[h]; 0);
fileEOF[FileH[h_], _] := Boole[TrueQ[feofFlag[h]]];
fileError[FileH[_], _] := 0;
fileErrno[_] := Switch[lastErrno, 2, 2, 13, 3, 17, 4, _, lastErrno + 5];
flushFile[FileH[_], _] := 0;
fileSize[FileH[h_], _] := If[StringQ[fbuf[h]], Length[ToCharacterCode[fbuf[h], "UTF-8"]],
  If[StringQ[fname[h]], Replace[Quiet[FileByteCount[fname[h]]], Except[_Integer] -> -1], -1]];
fileIsTTY[FileH[_], _] := 0;
removeFile[name_, _] := If[FileExistsQ[name] && !DirectoryQ[name],
  Quiet[DeleteFile[name]]; 0, setErrno[2]; -1];
stdinFile[] := FileH[0];
stdoutFile[] := FileH[1];
stderrFile[] := FileH[2];

(* ---- Directories ---- *)
(* Paths are those of the Windows kernel process (relative paths work). *)
currentDir[_] := Directory[];
changeDir[d_, _] := If[DirectoryQ[d], SetDirectory[d]; 0, setErrno[2]; -1];
createDir[d_, _] := Which[
  FileExistsQ[d], setErrno[17]; -1,
  !DirectoryQ[DirectoryName[ExpandFileName[d]]], setErrno[2]; -1,
  True, Quiet[CreateDirectory[d]]; 0];
removeDir[d_, _] := (Quiet[DeleteDirectory[d]]; unit);
dirCount = 0;
openDir[d_, _] := If[DirectoryQ[d],
  dirCount++; dentries[dirCount] = Join[{".", ".."}, FileNameTake /@ FileNames["*", d]];
  Dir[dirCount],
  setErrno[2]; nullPtr];
dirEntry[Dir[i_], _] := If[dentries[i] === {}, nullPtr,
  With[{e = First[dentries[i]]}, dentries[i] = Rest[dentries[i]]; e]];
closeDir[Dir[_], _] := unit;

(* ---- System ---- *)
exit[code_, _] := Exit[code];
(* argv: {script, args...}. wolframscript drops arguments starting with "-",
   so scripts/run-wl passes them in WOLFDRIS_ARGS (base64 of NUL-terminated
   UTF-8 strings; "-" for none). Otherwise fall back to $ScriptCommandLine. *)
decodeArgs["-"] = {};
decodeArgs[enc_String] := With[{bytes = Normal[BaseDecode[enc]]},
  With[{ends = Flatten[Position[bytes, 0]]},
    FromCharacterCode[#, "UTF-8"] & /@
      MapThread[Take[bytes, {#1 + 1, #2 - 1}] &, {Prepend[Most[ends], 0], ends}]]];
argv := argv = With[{enc = Environment["WOLFDRIS_ARGS"]},
  If[StringQ[enc] && enc =!= "",
    Prepend[decodeArgs[enc], First[$ScriptCommandLine, "main"]],
    $ScriptCommandLine]];
argCount[_] := Length[argv];
getArg[n_, _] := If[0 <= n < Length[argv], argv[[n + 1]], ""];
getEnv[v_, _] := Replace[Environment[v], $Failed -> nullPtr];
getEnvPair[n_, _] := With[{env = Normal[GetEnvironment[]]},
  If[0 <= n < Length[env], env[[n + 1, 1]] <> "=" <> env[[n + 1, 2]], nullPtr]];
setEnv[v_, val_, overwrite_, _] := (
  If[overwrite =!= 0 || Environment[v] === $Failed, SetEnvironment[v -> val]]; 0);
unsetEnv[v_, _] := (SetEnvironment[v -> None]; 0);
unixTime[_] := UnixTime[];
getPID[_] := $ProcessID;
sleepSec[s_, _] := (Pause[s]; unit);
sleepMicro[us_, _] := (Pause[us/10^6]; unit);
nProcessors[_] := $ProcessorCount;
termSetup[_] := unit;
termZero[_] := 0;

(* ---- Clocks (System.Clock); OSClock is ClockH[seconds, nanoseconds] ---- *)
toClock[t_] := With[{s = Floor[t]}, ClockH[s, Floor[(t - s) 10^9]]];
clockUtc[_] := toClock[AbsoluteTime[TimeZone -> 0] - AbsoluteTime[{1970}, TimeZone -> 0]];
clockMonotonic[_] := toClock[SessionTime[]];
clockCpu[_] := toClock[TimeUsed[]];
clockZero[_] := ClockH[0, 0];
clockValid[_, _] := 1;
clockSecond[ClockH[s_, _], _] := s;
clockNanosecond[ClockH[_, ns_], _] := ns;

(* %extern primitives (see extPrim in src/Wolfdris/Emit.idr). IORefs and
   arrays are handles into runtime-owned associations; nothing is freed. *)
refs = <||>; refCount = 0;
newIORef[v_] := (refCount++; refs[refCount] = v; Ref[refCount]);
readIORef[Ref[i_]] := refs[i];
writeIORef[Ref[i_], v_] := (refs[i] = v; unit);

arrays = <||>; arrCount = 0;
newArray[n_, v_] := (arrCount++; arrays[arrCount] = ConstantArray[v, Max[n, 0]]; Arr[arrCount]);
arrayGet[Arr[i_], k_] := If[0 <= k < Length[arrays[i]], arrays[i][[k + 1]],
  crash["arrayGet: index out of bounds"]];
arraySet[Arr[i_], k_, v_] := If[0 <= k < Length[arrays[i]],
  arrays[[Key[i], k + 1]] = v; unit,
  crash["arraySet: index out of bounds"]];

osName[] := Switch[$OperatingSystem, "Windows", "windows", "MacOSX", "darwin", _, "unix"];

(* Idris List <-> WL list, iteratively so long lists don't hit the
   recursion limit. Nil is Con[0], cons is Con[1, head, tail]. *)
conToList[l_] := Module[{x = l},
  Join @@ Reap[While[x[[1]] === 1, Sow[x[[2]]]; x = x[[3]]]][[2]]];
listToCon[xs_List] := Fold[Con[1, #2, #1] &, Con[0], Reverse[xs]];

fastPack[l_] := FromCharacterCode[conToList[l]];
fastUnpack[s_] := listToCon[ToCharacterCode[s]];
fastConcat[l_] := StringJoin[conToList[l]];

$ContextPath = WolfdrisRT`$savedContextPath;
End[];
