(* Paclet test: SalesTools (built from Main.idr), called the way a notebook
   would: with its own data, a file, and expressions in its own symbols. *)
dir = DirectoryName[$InputFileName];
globals := {$Messages, $RecursionLimit, $IterationLimit, $HistoryLength,
  Options[$Output, CharacterEncoding]};
before = globals;
show[label_, e_] := Print[label, ": ", ToString[e, InputForm]];

PacletDirectoryLoad[FileNameJoin[{dir, "build", "paclet", "SalesTools"}]];
Needs["SalesTools`"];

(* records from notebook data *)
data = {
  <|"region" -> "North", "year" -> 2021, "amount" -> 12.5, "note" -> "first"|>,
  <|"region" -> "South", "year" -> 2022, "amount" -> 7.|>,
  <|"region" -> "North", "year" -> 2022, "amount" -> 0.5, "extra" -> "ignored"|>};
show["totals", totals[data]];
show["a bad row", totals[Append[data, <|"region" -> "Mars", "year" -> 2021, "amount" -> 1.|>]]];
show["a missing field", totals[{<|"region" -> "East", "amount" -> 1.|>}]];

(* IO: a file *)
show["summarize", summarize[FileNameJoin[{dir, "sales.csv"}]]];
(* the message names the file; shown relative to this directory (Failure
   holds its contents, so take the message out first) *)
With[{r = summarize[FileNameJoin[{dir, "nope.csv"}]]},
  show["summarize a missing file", {Head[r], StringReplace[r[[2, "MessageTemplate"]], dir -> "<dir>"]}]];

(* expressions in the caller's own symbols *)
d = deriv[x^2 Sin[x], x];
show["deriv", d];
show["its symbols' contexts", Union[Context /@ Cases[d, _Symbol?(Context[#] =!= "System`" &), {0, Infinity}, Heads -> True]]];
show["deriv by y", deriv[x^2 y^3, y]];
show["taylor", taylor[Exp[x], x, 3]];
show["taylor with a parameter", taylor[Exp[a x], x, 2]];
show["no power series", taylor[Log[x], x, 2]];
show["not a variable", deriv[x^2, 3]];
(* a symbol with a value is substituted before the call, as for any WL function *)
x = 5;
show["x has a value", deriv[x^2, x]];
Clear[x];

(* IO output and crashes *)
show["boomIO[0]", boomIO[0]];
show["boomIO[1]", boomIO[1]];
show["after the crash", totals[Take[data, 1]]];

show["globals unchanged", globals === before];
