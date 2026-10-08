## What changed and why

## Checklist (see CONTRIBUTING.md)

- [ ] `bash scripts/check.sh` passes
- [ ] `Rscript scripts/offline-test.R` passes
- [ ] If I touched a helper: `Rscript scripts/selftest.R` passes (needs a Google login), and the helper has a row in `references/helpers.md`
- [ ] If I changed behavior: an eval is added or updated in `skills/r-googlesheets4/evals/`
- [ ] `SKILL.md` is still under 500 lines
- [ ] No real emails, sheet ids, company names or keys in the diff
- [ ] Nothing installs software or asks for broader Google access without an explicit user prompt
