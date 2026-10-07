#!/usr/bin/env bash
# Repo hygiene gate: fails on leaked identifiers, secrets and oversize SKILL.md.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
# Optional, never committed: put one regex per line in .blocklist (for example a
# former employer's name) and it is scanned for here. Keeps the terms out of the repo.
if [ -f .blocklist ]; then
  if grep -rniEf .blocklist --exclude-dir=.git --exclude=check.sh --exclude=.blocklist --exclude=claude.md . ; then
    echo "FAIL: blocked terms found"; fail=1; fi
fi
if grep -rnE "(client_secret|private_key|BEGIN (RSA )?PRIVATE KEY|refresh_token)" --exclude-dir=.git --exclude=check.sh --exclude=.gitignore --exclude=SECURITY.md --exclude=claude.md . ; then
  echo "FAIL: possible secret"; fail=1; fi
n=$(wc -l < skills/r-googlesheets4/SKILL.md)
if [ "$n" -gt 500 ]; then echo "FAIL: SKILL.md has $n lines (max 500)"; fail=1; fi
for f in skills/r-googlesheets4/scripts/*.R; do
  Rscript -e "invisible(parse('$f'))" >/dev/null 2>&1 || { echo "FAIL: R syntax error in $f"; fail=1; }
done
bash -n skills/r-googlesheets4/scripts/gs_setup.sh || fail=1
[ "$fail" -eq 0 ] && echo "OK"
exit "$fail"
