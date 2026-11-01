# Wolfdris highlight

Colours the names the Wolfdris `wolfram` package exports (`linearSolve`,
`integrate`, `nDSolve`, …) in Idris files, so Wolfram wrappers stand out
from your own functions, much like built-ins in a Wolfram notebook.
Hovering a coloured name says which library module it comes from.

Not coloured: names inside comments and strings, and names the Idris
Prelude also defines (`sin`, `exp`, `log`, `pi`, …), which the library
overloads for symbolic expressions. A local variable that happens to share
a library name (say `table`) is coloured too: the extension matches names,
it doesn't resolve them (the language server's hover does).

## Settings

- `wolfdris.highlight.color`: colour with a dark theme (default `#E8735A`)
- `wolfdris.highlight.lightColor`: colour with a light theme (default `#B4432A`)
- `wolfdris.highlight.fontStyle`: `normal`, `italic` or `bold`
- `wolfdris.highlight.enabled`

## Building

`scripts/vscode-extension.sh` (from the repository) regenerates the name
list from `lib/` and builds `editor/vscode/build/wolfdris-highlight.vsix`;
install it with `code --install-extension <file>`. Rebuild after adding
wrappers.
