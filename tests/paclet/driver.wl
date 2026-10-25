(* Paclet test: load the paclets built from Main.idr (PolyFit, and the same
   program as PolyFit2) and call them the way a notebook would.
   Numeric results are rounded to exact thousandths so the output doesn't
   depend on WL's last digits. *)
dir = FileNameJoin[{DirectoryName[$InputFileName], "build", "paclet"}];
globals := {$Messages, $RecursionLimit, $IterationLimit, $HistoryLength,
  Options[$Output, CharacterEncoding]};
before = globals;
contexts = $ContextPath;
show[label_, e_] := Print[label, ": ", ToString[e, InputForm]];
r3[e_] := Round[1000 e]/1000;

PacletDirectoryLoad[FileNameJoin[{dir, "PolyFit"}]];
PacletDirectoryLoad[FileNameJoin[{dir, "PolyFit2"}]];
Needs["PolyFit`"];
(* same names in two contexts on $ContextPath: WL warns, as it would for any
   two packages *)
Quiet[Needs["PolyFit2`"], General::shdw];
show["added contexts", Sort[Complement[$ContextPath, contexts]]];
show["usage", PolyFit`fit::usage];

xs = Range[-2., 2.5, 0.5];
ys = (xs + 1.5) (xs - 1.) (xs - 2.);
show["fit", r3[PolyFit`fit[3, xs, ys]]];
show["roots", Sort[r3[PolyFit`roots[{3., -2.5, -1.5, 1.}]]]];
show["complex roots", Sort[r3[PolyFit`roots[{1., 0., 1.}]]]];
show["heads", Head /@ PolyFit`roots[{1., 0., 1.}]];
show["solve", r3[PolyFit`solve[{{2., 1., -1.}, {-3., -1., 2.}, {-2., 1., 2.}}, {8., -11., -3.}]]];
show["greet", PolyFit`greet["W\[ODoubleDot]rld"] === "Hello, W\[ODoubleDot]rld!"];

(* failures: each is a Failure, and the kernel carries on *)
show["no solution", PolyFit`solve[{{1., 2.}, {2., 4.}}, {1., 1.}]];
show["not square", PolyFit`solve[{{1., 2.}}, {1., 1.}]];
show["lengths differ", PolyFit`fit[3, {1.}, {1., 2.}]];
show["leading zero", PolyFit`roots[{1., 0.}]];
show["arity", PolyFit`fit[3, xs]];
show["wrong type", PolyFit`fit[-1, xs, ys]];
show["wrong element", PolyFit`roots[{1., "a"}]];
show["crash", PolyFit`boom[1]];
show["after the crash", PolyFit`boom[0]];
show["deep recursion", PolyFit`sumTo[100000]];
show["second paclet", PolyFit2`sumTo[10]];

show["globals unchanged", globals === before];
