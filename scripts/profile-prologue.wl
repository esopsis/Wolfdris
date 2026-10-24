(* Call-count profiler for generated programs, used by scripts/profile.sh,
   which rewrites the program's final runMain[...] into profMain[...]. *)
SetAttributes[profMain, HoldAll];
profCount = <||>;
profMain[main_] := Module[{syms, t},
  syms = Select[Names["WolfdrisGen`*"], DownValues[#] =!= {} &];
  Scan[With[{s = Symbol[#], name = #},
      DownValues[s] = Prepend[DownValues[s],
        HoldPattern[s[___]] :> Null /; (profCount[name] = Lookup[profCount, name, 0] + 1; False)]] &,
    syms];
  (* primitives: one counter per (op, type) *)
  SubValues[WolfdrisRT`op] = Prepend[SubValues[WolfdrisRT`op],
    HoldPattern[WolfdrisRT`op[k__][___]] :> Null /;
      (profCount[{k}] = Lookup[profCount, Key[{k}], 0] + 1; False)];
  t = First[AbsoluteTiming[TimeConstrained[CheckAbort[main, Print["aborted"]], 600, Print["timeout"]]]];
  Print["---- ", Round[t, 0.1], " s, ", Total[profCount], " counted calls"];
  (* group lifted definitions by kind: let12 -> let, cont3 -> cont *)
  With[{short = StringReplace[#, {"WolfdrisGen`" -> "", RegularExpression["^(let|cont|lam|alt|case|join|thunk|delay)[0-9]+$"] -> "<$1>"}] &},
    Print["by kind: ", TakeLargest[Merge[KeyValueMap[If[StringQ[#1], short[#1], "op"] -> #2 &, profCount], Total], 8]];
    Print["top 30:"];
    Scan[Print["  ", #[[2]], "  ", If[StringQ[#[[1]]], short[#[[1]]], #[[1]]]] &,
      List @@@ Normal[TakeLargest[profCount, 30]]]];
  Exit[0]];
