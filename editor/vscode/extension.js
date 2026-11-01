// Colours the names the Wolfdris `wolfram` package exports in Idris files,
// so Wolfram wrappers stand out from your own functions. The names come
// from names.json (generated from lib/ by scripts/vscode-extension.sh).
// Decorations are drawn over the theme's and the language server's colours.
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");

let names = {};
let wordRe = null;
let decoration = null;
let timer = null;

function loadNames(context) {
  names = JSON.parse(fs.readFileSync(path.join(context.extensionPath, "names.json"), "utf8"));
  const alts = Object.keys(names).sort((a, b) => b.length - a.length).join("|");
  // a whole identifier: not part of a longer name (Idris names may contain ' and _)
  wordRe = alts ? new RegExp(`(?<![A-Za-z0-9_'])(?:${alts})(?![A-Za-z0-9_'])`, "g") : null;
}

function makeDecoration() {
  const cfg = vscode.workspace.getConfiguration("wolfdris.highlight");
  if (decoration) decoration.dispose();
  const style = cfg.get("fontStyle");
  decoration = vscode.window.createTextEditorDecorationType({
    dark: { color: cfg.get("color") },
    light: { color: cfg.get("lightColor") },
    fontStyle: style === "italic" ? "italic" : undefined,
    fontWeight: style === "bold" ? "bold" : undefined,
  });
}

// Ranges of comments (--, |||, {- -} nested) and string/char literals,
// where names are not coloured.
function skipRanges(text) {
  const ranges = [];
  let i = 0;
  while (i < text.length) {
    const c = text[i];
    if (c === "-" && text[i + 1] === "-") {
      const end = text.indexOf("\n", i);
      ranges.push([i, end < 0 ? text.length : end]);
      i = end < 0 ? text.length : end;
    } else if (c === "|" && text.startsWith("|||", i)) {
      const end = text.indexOf("\n", i);
      ranges.push([i, end < 0 ? text.length : end]);
      i = end < 0 ? text.length : end;
    } else if (c === "{" && text[i + 1] === "-") {
      let depth = 1, j = i + 2;
      while (j < text.length && depth > 0) {
        if (text[j] === "{" && text[j + 1] === "-") { depth++; j += 2; }
        else if (text[j] === "-" && text[j + 1] === "}") { depth--; j += 2; }
        else j++;
      }
      ranges.push([i, j]);
      i = j;
    } else if (c === '"') {
      let j = i + 1;
      while (j < text.length && text[j] !== '"' && text[j] !== "\n") j += text[j] === "\\" ? 2 : 1;
      ranges.push([i, j + 1]);
      i = j + 1;
    } else i++;
  }
  return ranges;
}

function update(editor) {
  if (!editor || editor.document.languageId !== "idris" || !decoration) return;
  const enabled = vscode.workspace.getConfiguration("wolfdris.highlight").get("enabled");
  if (!enabled || !wordRe) { editor.setDecorations(decoration, []); return; }
  const text = editor.document.getText();
  const skip = skipRanges(text);
  const found = [];
  let k = 0;
  wordRe.lastIndex = 0;
  for (let m; (m = wordRe.exec(text)); ) {
    while (k < skip.length && skip[k][1] <= m.index) k++;
    if (k < skip.length && skip[k][0] <= m.index) continue;
    const range = new vscode.Range(editor.document.positionAt(m.index),
                                   editor.document.positionAt(m.index + m[0].length));
    found.push({ range, hoverMessage: `Wolfdris library: \`${names[m[0]]}\`` });
  }
  editor.setDecorations(decoration, found);
}

function updateVisible() {
  for (const editor of vscode.window.visibleTextEditors) update(editor);
}

function activate(context) {
  loadNames(context);
  makeDecoration();
  updateVisible();
  context.subscriptions.push(
    vscode.window.onDidChangeVisibleTextEditors(updateVisible),
    vscode.workspace.onDidChangeTextDocument((e) => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        for (const editor of vscode.window.visibleTextEditors)
          if (editor.document === e.document) update(editor);
      }, 200);
    }),
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("wolfdris.highlight")) { makeDecoration(); updateVisible(); }
    }),
    { dispose: () => decoration && decoration.dispose() });
}

module.exports = { activate, deactivate() {} };
