# Contributing

Thanks for helping. This skill stays small on purpose: one skill, plain R scripts,
no hidden installs.

## Before you open a pull request

1. Keep `skills/r-googlesheets4/SKILL.md` under 500 lines; put detail in `references/`.
2. Never add anything that installs software or requests broader Google access
   without an explicit user prompt.
3. No real emails, sheet IDs, company names or keys in examples. Use `you@example.com`
   and `gs4_example()`.
4. Run the checks: `claude plugin validate --strict .` and `bash scripts/check.sh`
   (secret and branding scan).
5. For a behavior change, add or update an eval in `skills/r-googlesheets4/evals/`.
   Run evals as a dry run: give the model the skill and a scripted command output, and
   ask for an action log (commands it would run plus the final message). Asking for a
   full reasoning transcript can trip model safeguards.

## Style

- Match the surrounding R: snake_case helpers, `fmt_*` for batchUpdate request builders.
- Document a new helper in `references/helpers.md`.
- Credit the R packages you build on (see `THIRD_PARTY_NOTICES.md`).
