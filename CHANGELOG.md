# Changelog

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
