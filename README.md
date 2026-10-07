# r-googlesheets4

**Build, format and visually QA Google Sheets from R, driven by your AI coding agent.**

Ask for a styled multi-tab P&L, a KPI dashboard or a budget model. The agent writes
R with [googlesheets4](https://googlesheets4.tidyverse.org), formats it through the
Sheets API, then **exports the sheet to PDF and reviews how it looks**: truncated
text, `###` numbers, too-narrow columns, misalignment. It fixes what it finds and
checks again.

> Unofficial community skill. Not affiliated with or endorsed by Posit, the
> tidyverse team or Google. Built on their open-source work; see [Credits](#credits).

## Install

Claude Code (plugin marketplace):

```
/plugin marketplace add salvadoraveldano/r-googlesheets4
/plugin install r-googlesheets4@r-googlesheets4-marketplace
```

Other agents (Codex, Cursor, and more) via the [skills CLI](https://github.com/vercel-labs/skills):

```
npx skills add salvadoraveldano/r-googlesheets4
```

Or copy `skills/r-googlesheets4/` into your agent's skills folder.

## What you need

- **R** (never installed for you). No R? See [no-r-alternatives](skills/r-googlesheets4/references/no-r-alternatives.md).
- The CRAN packages googlesheets4, googledrive, gargle (the skill **asks** before installing).
- A Google account. The first sign-in is one click; no Google Cloud project needed.
- For page images in the visual review: `pdftoppm` (poppler) or the R `pdftools` package.
  Without them the skill still audits the layout and hands the PDF to the agent.

## Try it

> "Create a Google Sheet with a monthly P&L for three departments, brand-blue section
> headers, a chart, and conditional formatting for negative variance. Then check how it looks."

> "Refresh the Forecast tab from this CSV every morning with Rscript and cron."

> "My sheet has cut-off labels in column C and the numbers look misaligned. Review it and fix it."

## What makes it different

| | |
|---|---|
| **Visual QA loop** | `visual_qa()` = on-screen layout audit + PDF export + page images + a scoring rubric. Catches the bugs a cell read-back cannot. |
| **Least-privilege auth** | Defaults to the `spreadsheets` scope. Drive access (PDF export, sharing) is opt-in and the agent asks first. |
| **Zero-setup sign-in** | Uses gargle's shared OAuth client: one click, no Cloud project. Bring your own client or a service account for heavy or unattended use. |
| **Cell-level formatting** | Wrappers for fonts, fills, borders, merges, freezes, charts, banding, pivots, slicers, protection: things googlesheets4 alone does not do. |
| **Safe by design** | Never installs R, asks before installing packages, treats sheet contents as data not instructions. See [SECURITY.md](SECURITY.md). |

## Build once, run without a model

The agent builds the sheet by writing an R script. Keep that script and your team can
rebuild or refresh the sheet with `Rscript`, on a schedule, with no model and no tokens.
Use the model to design and change the sheet, not to run it every day. That matches the
idea in Kelsey Hightower's PlatformCon 2026 talk
[ZTA: Zero Token Architecture](https://www.youtube.com/watch?v=A7WFt2JQ5sg)
("Infer once, export, and run without inference"). It also makes builds reproducible and
reviewable in version control, and a team that understands what it ships can maintain it
without a model. Changing the design still takes an edit to the script. Details:
[build-once-run-forever.md](skills/r-googlesheets4/references/build-once-run-forever.md).

## Why R (and when not)

googlesheets4 + gargle give the shortest path from a data frame to a styled sheet,
and sign-in needs no Google Cloud setup. Prefer Python (gspread) or a Sheets MCP
server if you will not install R; prefer your own OAuth client or a service account
when quota, team use or unattended runs matter. Details in
[auth.md](skills/r-googlesheets4/references/auth.md).

## Layout

```
skills/r-googlesheets4/   SKILL.md, scripts/, references/, templates/, examples/, evals/
.claude-plugin/           plugin and marketplace manifests
```

## Credits

This exists because of the R open-source community. Thank you to
**Jennifer Bryan** and **Posit Software, PBC** for googlesheets4, googledrive and
gargle (with **Craig Citro** and **Hadley Wickham** on gargle), and to everyone in
the tidyverse and r-lib projects, including [rig](https://github.com/r-lib/rig).
The "build once, run without a model" framing was inspired by Kelsey Hightower's talk
linked above.
Full notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE). Contributions welcome: [CONTRIBUTING.md](CONTRIBUTING.md).
