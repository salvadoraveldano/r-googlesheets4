# Showcases

Three sample Google Sheets, each built by one R script from synthetic data. Every row is generated with `set.seed()`, so there are no real people, merchants, accounts or amounts. The scripts show what the skill builds and give you a working base to copy.

| Sheet | Script | Tabs | What it shows |
|---|---|---|---|
| SaaS Financial Model | `saas-model.R` | 8 | A 24-month, driver-based model. One scenario dropdown (Base, Upside, Downside) drives every tab through named ranges. The Summary tab has KPI cards with sparklines, an MRR waterfall, an ARR-by-scenario chart and a scenario table. A Checks tab runs 17 integrity checks and feeds a status badge. |
| Ops Command Center | `ops-command-center.R` | 5 | A project dashboard. KPI cards, a status doughnut, a workstream bar chart, planned-versus-actual burn-down, a top-5 "needs attention" list, 45 tasks with dropdowns and sparkline progress bars, a weekly Gantt drawn by conditional formatting, and an owner-by-status workload heatmap. |
| Personal Finance Tracker | `personal-finance.R` | 6 | A month picker drives the dashboard: KPI cards, a budget-health strip, four charts and a top-5 list. Budget, Transactions (about 370 rows), Net Worth and Trends tabs sit behind it, with SUMIFS actuals, red and green variance rules, a native pivot-table heatmap and live self-checks. |

## Live samples

View-only links, the same sheets the screenshots come from. The dropdowns and pickers only work in your own copy (File > Make a copy, or the copy links).

- SaaS Financial Model: [open](https://docs.google.com/spreadsheets/d/1N5A_YHreexPraNFuU7XaKrnTCCQXvsmYY7HZHUpMNlQ/edit?usp=sharing) · [copy](https://docs.google.com/spreadsheets/d/1N5A_YHreexPraNFuU7XaKrnTCCQXvsmYY7HZHUpMNlQ/copy)
- Ops Command Center: [open](https://docs.google.com/spreadsheets/d/15d2XnvqlwJ4HqnrRCHAgfmw4N5eZq7-CuSFQO6MP73M/edit?usp=sharing) · [copy](https://docs.google.com/spreadsheets/d/15d2XnvqlwJ4HqnrRCHAgfmw4N5eZq7-CuSFQO6MP73M/copy)
- Personal Finance Tracker: [open](https://docs.google.com/spreadsheets/d/1dPKbynmhf3x_9pFuIMvOOBnjIMmAf4Nw9ot3fFmDVs4/edit?usp=sharing) · [copy](https://docs.google.com/spreadsheets/d/1dPKbynmhf3x_9pFuIMvOOBnjIMmAf4Nw9ot3fFmDVs4/copy)

## Build your own copy

You need the skill's setup done once: R, the CRAN packages and a saved Google login (`bash skills/r-googlesheets4/scripts/gs_setup.sh status`). Run from the repository root:

```
GS_SKILL_DIR=skills/r-googlesheets4 Rscript examples/showcases/saas-model.R
```

The script creates a new file in your Drive and prints its id. To rebuild that same file after editing the script:

```
SHEET_ID=<id> GS_SKILL_DIR=skills/r-googlesheets4 Rscript examples/showcases/saas-model.R
```

A rerun clears the tabs it builds, so use it only on a file the script made. The script refuses a `SHEET_ID` that points at a file with another title and without these tabs, or with another locale, and changes nothing in that case. Rerunning needs no model. The scripts use the default access level (spreadsheets scope only), never touch Drive and never share anything.

Each script ends by reading the sheet back from Google and stops with an error if a check fails: error values, chart counts, or a status cell that does not read as expected.

## Known rough edges

- PDF export repeats frozen rows on every page and can split a wide dashboard across pages. The sheets look right on screen; this only affects the PDF.
- In the Ops sheet, the saved filter views list tasks with a blank owner.
- A view-only visitor cannot use dropdowns, so the input cells look inactive. Use File > Make a copy to try them.

Built with the [r-googlesheets4 skill](../../README.md), on googlesheets4 and gargle by Jennifer Bryan and Posit.
