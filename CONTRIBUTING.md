# Contributing

Thanks for contributing. The skill is small on purpose: one skill, plain R scripts
and no hidden installs.

## Before you open a pull request

1. Keep `skills/r-googlesheets4/SKILL.md` under 500 lines; put detail in `references/`.
2. Never add anything that installs software or requests broader Google access
   without an explicit user prompt.
3. No real emails, sheet IDs, company names or keys in examples. Use `you@example.com`
   and `gs4_example()`. The one exception is the links to the three published sample
   sheets, which are in the docs; the scripts keep the `<id>` placeholder.
4. Run the checks: `bash scripts/check.sh` (secret and branding scan, R syntax, version
   sync, and a gate that fails when a helper in `scripts/` has no row in
   `references/helpers.md`), `Rscript scripts/offline-test.R` (request shapes and guards,
   no Google account needed; it needs the CRAN packages googlesheets4, googledrive, httr
   and glue) and `claude plugin validate --strict .`. Validate a clean checkout: a local,
   untracked `claude.md` at the repo root makes `--strict` fail.
5. If you touched a helper, run the live self-test: `Rscript scripts/selftest.R`. It
   needs a saved login (see [auth.md](skills/r-googlesheets4/references/auth.md)),
   uses one scratch sheet at the default access level, and prints a PASS/FAIL table.
   Every row must pass.
6. For a behavior change, add or update an eval in `skills/r-googlesheets4/evals/`.
   Run evals as a dry run: give the model the skill and a scripted command output, and
   ask for an action log (the commands it would run, plus the final message). Don't ask
   for a full reasoning transcript, which can trip model safeguards. Last graded
   2026-10-08: all 17 evals on Haiku, and evals 14 to 17 on Sonnet and Opus. One
   expectation (`share-exposure`: give the exact `GS_SCOPE_LEVEL=drive` sign-in command) failed
   on Sonnet and Opus, so SKILL.md now states the command, and both passed on a re-run.

## Style

- Match the surrounding R: snake_case helpers, `fmt_*` for batchUpdate request builders.
- A new helper needs a row in `references/helpers.md` and a check in `scripts/selftest.R`.
  `scripts/check.sh` fails if the row is missing.
- Credit the R packages you build on (see `THIRD_PARTY_NOTICES.md`).
