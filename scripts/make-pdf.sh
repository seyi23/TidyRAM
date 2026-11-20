#!/bin/zsh
#
# make-pdf.sh – erzeugt docs/TidyRAM.pdf aus README.md
#
# Ablauf: README.md → HTML (Python-Paket "markdown") → PDF (Chrome headless).
# Beim ersten Lauf wird eine lokale Python-Umgebung .venv/ angelegt.
#
# Benötigt: Python 3, Google Chrome.
#
set -euo pipefail
cd "${0:A:h}/.."
ROOT=$PWD

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -x "$CHROME" ]] || { echo "Google Chrome nicht gefunden: $CHROME" >&2; exit 1; }

# Python-Umgebung mit dem markdown-Paket (einmalig).
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
  .venv/bin/pip install --quiet markdown
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Markdown → HTML mit Druck-Stylesheet.
.venv/bin/python - "$ROOT" "$TMP/doc.html" <<'PY'
import sys, pathlib, markdown
from markdown.extensions.toc import slugify_unicode

root, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
md = (root / "README.md").read_text(encoding="utf-8")
body = markdown.markdown(
    md,
    extensions=["tables", "fenced_code", "toc", "sane_lists"],
    extension_configs={"toc": {"slugify": slugify_unicode}},
)

css = """
@page { size: A4; margin: 18mm 16mm 20mm; }
:root { --accent: #2f6fdf; --muted: #5b6270; --line: #dfe3ea; --code: #f4f6f9; }
* { box-sizing: border-box; }
body { font: 10.5pt/1.55 -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif;
       color: #1d2129; margin: 0; }
h1 { font-size: 26pt; margin: 0 0 6pt; letter-spacing: -0.5pt; }
h1 + p { font-size: 12pt; color: var(--muted); margin-top: 0; }
h2 { font-size: 15pt; color: var(--accent); margin: 22pt 0 8pt; padding-bottom: 4pt;
     border-bottom: 1.5pt solid var(--accent); break-after: avoid; }
h3 { font-size: 12pt; margin: 16pt 0 6pt; break-after: avoid; }
h4 { font-size: 10.5pt; margin: 12pt 0 4pt; break-after: avoid; }
hr { display: none; }
a { color: var(--accent); text-decoration: none; }
p, li { orphans: 3; widows: 3; }
img { display: block; margin: 8pt auto; }
table { width: 100%; border-collapse: collapse; margin: 8pt 0 12pt; font-size: 9.5pt;
        break-inside: avoid; }
th { text-align: left; background: #eef2f8; font-weight: 600; }
th, td { border: 0.75pt solid var(--line); padding: 4pt 6pt; vertical-align: top; }
code { font: 8.8pt/1.45 "SF Mono", Menlo, monospace; background: var(--code);
       padding: 0.5pt 3pt; border-radius: 3pt; }
pre { background: var(--code); border: 0.75pt solid var(--line); border-radius: 5pt;
      padding: 7pt 9pt; white-space: pre-wrap; word-break: break-all; break-inside: avoid; }
pre code { background: none; padding: 0; }
blockquote { margin: 8pt 0; padding: 6pt 10pt; border-left: 3pt solid #e0a800;
             background: #fff8e1; color: #4a4030; }
blockquote p { margin: 2pt 0; }
"""
html = f"""<!doctype html><html lang="de"><head><meta charset="utf-8">
<base href="{root.as_uri()}/"><title>TidyRAM – Dokumentation</title>
<style>{css}</style></head><body>{body}</body></html>"""
out.write_text(html, encoding="utf-8")
PY

# HTML → PDF
mkdir -p docs
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
  --allow-file-access-from-files \
  --print-to-pdf="$ROOT/docs/TidyRAM.pdf" "file://$TMP/doc.html" 2>/dev/null

echo "Fertig: $ROOT/docs/TidyRAM.pdf"
