# Changelog

## 3.0.1 (unreleased)

- **Fix:** `audit_layout()` now reports a clipped merged title as "merged cells A:D are
  N px wide" and suggests widening the merged columns in total (it used to suggest
  widening one column to the full text width).
- New `gs_open_or_create()`: rebuild into the same sheet with `SHEET_ID=<id>` instead of
  leaving a new file in Drive on every fix loop. Templates and examples use it.
- SKILL.md and the review rubric: state only what you observed (do not describe page
  images or scripts you did not read).
- A clear user instruction to install what is needed counts as consent for the three CRAN
  packages (never for R, access levels, sharing or the account choice).
- Evals: forbidden-action expectations added, and six new cases (blanket "just install",
  background sign-in, blocked port, injection in a tab name, missing rasterizer, cron).

## 3.0.0 (unreleased)

First public release.

- Employer-specific branding removed; `brand.R` is a generic, editable theme.
- **Least-privilege auth:** default access level is `spreadsheets`; `readonly`,
  `export` and `drive` are opt-in (`GS_SCOPE_LEVEL`).
- **Visual QA built in:** `audit_layout()` and `visual_qa()` (layout audit, PDF
  export, page images) plus a review rubric. No separate reviewer skill needed.
- Never installs R; asks before installing R packages; prints OS-specific R install options.
- SKILL.md rewritten for progressive disclosure (under 250 lines), portable paths, MIT license.
- Third-party credits and security policy added.
