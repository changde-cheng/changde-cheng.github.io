#!/usr/bin/env bash
# Fail the build if any rendered page loads JavaScript from a third-party host.
#
# Runs as a Quarto post-render hook (see _quarto.yml).
#
# Why this exists:
#   Quarto 1.3 injects <script src="https://polyfill.io/v3/polyfill.min.js"> into every
#   page that uses MathJax.  polyfill.io was sold in 2024 and used to serve malware to
#   visitors.  Deleting the tag from docs/*.html by hand does not hold -- the next render
#   writes it back, which is exactly what happened between commits 999e9f0 and 941fa4f.
#
#   The real fix is html-math-method: katex pointed at the vendored katex/ directory.
#   This script is the guard that proves the fix is still in force: a rule that fires as
#   code survives across renders, a rule that fires as memory does not.
#
# Usage:  bash scripts/check_external_scripts.sh [output-dir]     (default: docs)

set -euo pipefail

OUT_DIR="${1:-${QUARTO_PROJECT_OUTPUT_DIR:-docs}}"

if [ ! -d "$OUT_DIR" ]; then
  echo "check_external_scripts: output dir '$OUT_DIR' not found -- nothing to check" >&2
  exit 0
fi

# Two ways a page can pull third-party JavaScript, and both must be checked:
#
#   1. a literal tag            <script src="https://...">  /  <link href="https://...">
#   2. a runtime assignment     script.src = "https://..."
#
# Pattern 2 is not cosmetic.  Quarto's lazy MathJax loader builds the CDN URL in JS, so a
# tag-shaped check alone reports a clean PASS on a page that still fetches a remote script.
# Everything this site needs is served from site_libs/ or katex/, so there should be none.
findings=$(grep -rnoIE '<(script|link)[^>]+(src|href)="https?://[^"]+"|\.src[[:space:]]*=[[:space:]]*"https?://[^"]+"' \
             "$OUT_DIR" --include='*.html' 2>/dev/null || true)

if [ -n "$findings" ]; then
  echo "" >&2
  echo "check_external_scripts: FAIL -- rendered pages load third-party assets:" >&2
  echo "" >&2
  echo "$findings" >&2
  echo "" >&2
  echo "Every asset must be served from this repo (site_libs/ or katex/)." >&2
  echo "If math is involved, confirm _quarto.yml still sets:" >&2
  echo "    html-math-method: {method: katex, url: /katex/}" >&2
  echo "See katex/README.md for the full story." >&2
  exit 1
fi

# The vendored KaTeX must actually be present in the output, or math pages render raw TeX.
if grep -rqI 'katex' "$OUT_DIR" --include='*.html' 2>/dev/null; then
  for asset in katex.min.js katex.min.css; do
    if [ ! -f "$OUT_DIR/katex/$asset" ]; then
      echo "check_external_scripts: FAIL -- pages reference KaTeX but $OUT_DIR/katex/$asset is missing." >&2
      echo "Check that _quarto.yml lists  resources: - \"katex/**\"" >&2
      exit 1
    fi
  done
fi

echo "check_external_scripts: PASS -- no third-party scripts or stylesheets in $OUT_DIR/"
