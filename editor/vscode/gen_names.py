"""Write names.json: the lowercase functions the wolfram package exports.

Names that the Idris Prelude also defines (sin, exp, log, pi, ...) are
left out: the library overloads them for Expr, so colouring them would
also mark ordinary Double code.

Usage: python3 gen_names.py <repo> <prelude source dir> <out.json>
"""
import json
import pathlib
import re
import sys

repo, prelude_dir, out = map(pathlib.Path, sys.argv[1:4])

# `export` / `public export` followed by `name :`, on the same line or the next
export_re = re.compile(r"^(?:public )?export\b[ \t]*\n?[ \t]*([a-z][A-Za-z0-9_']*)[ \t]*:", re.M)
# any top-level or interface-method declaration in the Prelude
decl_re = re.compile(r"^[ \t]*([a-z][A-Za-z0-9_']*)[ \t]*:[^:]", re.M)

ours = {}
for f in sorted((repo / "lib" / "src").rglob("*.idr")):
    module = ".".join(f.relative_to(repo / "lib" / "src").with_suffix("").parts)
    for name in export_re.findall(f.read_text(encoding="utf-8")):
        ours.setdefault(name, module)

prelude = set()
for f in prelude_dir.rglob("*.idr"):
    prelude.update(decl_re.findall(f.read_text(encoding="utf-8")))

names = {n: m for n, m in sorted(ours.items()) if n not in prelude}
skipped = sorted(n for n in ours if n in prelude)
out.write_text(json.dumps(names, indent=1) + "\n", encoding="utf-8")
print(f"{len(names)} names -> {out}; left uncoloured (also in the Prelude): {' '.join(skipped)}")
