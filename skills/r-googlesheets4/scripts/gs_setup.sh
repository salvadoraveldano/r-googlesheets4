#!/usr/bin/env bash
# =============================================================================
# gs_setup.sh — entry point for connecting the r-googlesheets4 skill to Google
# =============================================================================
# Finds Rscript (even when it is not on PATH) and forwards to gs_setup.R.
# Never installs R: when it is missing this prints the options and stops.
# Run from the skill directory (or use the absolute path to this file).
#
#   bash scripts/gs_setup.sh status  [email]
#   bash scripts/gs_setup.sh install
#   bash scripts/gs_setup.sh auth    [email]
#   bash scripts/gs_setup.sh verify  [email]
#
# The LAST line of stdout is always machine-readable:
#   GS_SETUP state=<STATE> email=<x|-> reason=<..|-> next=<command|-> [cached=...]
# States / exit codes: READY,INSTALLED=0  NEEDS_R=2  NEEDS_INSTALL=3
#                      NEEDS_EMAIL=4  NEEDS_AUTH=5  AUTH_FAILED=6  ERROR=1
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RSCRIPT=""
if command -v Rscript >/dev/null 2>&1; then
  RSCRIPT="$(command -v Rscript)"
else
  # Windows (Git Bash): the CRAN installer does not put R on PATH. Newest version wins.
  # Untested on a real Windows machine; scripts/check.sh tests this lookup on a fake tree.
  for base in "${PROGRAMFILES:-}" "/c/Program Files"; do
    [ -n "$base" ] || continue
    base="$(cygpath -u "$base" 2>/dev/null || printf '%s' "$base")"
    c="$(ls -d "$base"/R/R-*/bin/Rscript.exe 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$c" ] && [ -x "$c" ]; then RSCRIPT="$c"; break; fi
  done
  [ -n "$RSCRIPT" ] || for c in /usr/local/bin/Rscript /opt/homebrew/bin/Rscript \
           /Library/Frameworks/R.framework/Resources/bin/Rscript \
           /usr/bin/Rscript /usr/lib/R/bin/Rscript; do
    if [ -x "$c" ]; then RSCRIPT="$c"; break; fi
  done
fi

if [ -z "$RSCRIPT" ]; then
  cat <<'MSG'
[gs_setup] R is not installed on this computer (no Rscript found). Nothing was installed.
[gs_setup] Pick one option, install it yourself, then re-run this command:
[gs_setup]   Any OS      CRAN installer          https://cloud.r-project.org
[gs_setup]   Any OS      rig (version manager)   https://github.com/r-lib/rig
[gs_setup]   macOS       Homebrew                brew install --cask r
[gs_setup]   Linux       Posit builds            https://docs.posit.co/resources/install-r.html
[gs_setup]   No R at all see references/no-r-alternatives.md (Python gspread or a Sheets MCP server)
MSG
  echo "GS_SETUP state=NEEDS_R email=- reason=no-rscript next=install-r-then-rerun"
  exit 2
fi

exec "$RSCRIPT" "$HERE/gs_setup.R" "$@"
