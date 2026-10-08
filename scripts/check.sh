#!/usr/bin/env bash
# Repo hygiene gate: fails on leaked identifiers, secrets, an oversize SKILL.md, R syntax
# errors, and docs that drifted from the code (a helper without a helpers.md row, a
# SKILL.md link to a reference file that is not there).
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
bash -n skills/r-googlesheets4/scripts/gs_setup.sh || fail=1

# Every references/*.md file that SKILL.md mentions must exist.
for p in $(grep -oE 'references/[A-Za-z0-9_.-]+\.md' skills/r-googlesheets4/SKILL.md | sort -u || true); do
  [ -f "skills/r-googlesheets4/$p" ] || { echo "FAIL: SKILL.md mentions $p, which does not exist"; fail=1; }
done

# One R process for both R checks (a start-up per file would be slow).
Rscript - <<'EOF' || fail=1
bad <- 0L
say <- function(...) { cat("FAIL: ", ..., "\n", sep = ""); bad <<- bad + 1L }

# 1. Parse every R file under skills/, examples/ and scripts/ (helpers, templates, showcases, self-test).
for (f in list.files(c("skills", "examples", "scripts"),"\\.R$", recursive = TRUE, full.names = TRUE)) {
  err <- tryCatch({ parse(f, keep.source = FALSE); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(err)) say("R syntax error in ", f, " at ", sub(paste0(f, ":"), "", strsplit(err, "\n")[[1]][1], fixed = TRUE))
}

# 2. Doc drift: every top-level function in scripts/*.R needs a table row in
#    references/helpers.md that names it in backticks, such as | `fmt_cells()` |.
#    A name left out on purpose goes below, with the reason.
scripts <- "skills/r-googlesheets4/scripts"
skip_files <- c(
  "gs_setup.R")          # CLI driver run by gs_setup.sh and never sourced: all its functions are internals
internal <- c(
  "quote_criteria",      # internal to f_sumifs()
  # Auth plumbing behind gs_connect(); scripts call gs_connect() and auth.md describes the rest.
  "gs_config_path", "gs_config_email", "gs_save_config_email", "gs_resolve_email",
  "gs_oauth_cache", "gs_cached_logins", "gs_has_login", "gs_live_check")
rows <- grep("^\\s*\\|", readLines("skills/r-googlesheets4/references/helpers.md"), value = TRUE)
is_fun_def <- function(e) is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && length(e) == 3L &&
  (is.name(e[[2]]) || is.character(e[[2]])) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))
for (f in setdiff(Sys.glob(file.path(scripts, "*.R")), file.path(scripts, skip_files))) {
  ex <- tryCatch(parse(f, keep.source = FALSE), error = function(e) NULL)   # a syntax error is reported above
  for (e in ex) {
    if (!is_fun_def(e)) next
    nm <- as.character(e[[2]])
    if (!grepl("^[A-Za-z]", nm) || nm %in% internal) next                  # .dot helpers and operators are private
    named <- function(tag) any(grepl(tag, rows, fixed = TRUE))
    if (!named(paste0("`", nm, "(")) && !named(paste0("`", nm, "`")))
      say(f, " defines ", nm, "() but references/helpers.md has no table row naming `", nm,
          "` (add a row, or list it under `internal` in scripts/check.sh with a reason)")
  }
}
if (bad > 0L) quit(status = 1L)
EOF

[ "$fail" -eq 0 ] && echo "OK"
exit "$fail"
