# Visual Review Rubric

Cell values can be right while the sheet looks wrong. This is the loop that
catches it. Run it on every build before declaring done.

## The loop (max 3 iterations)

```r
source("scripts/gs_qa.R"); source("scripts/gs_visual_qa.R")
qa <- visual_qa(ss)            # layout audit + PDF + PNG pages for every tab
qa$findings                    # tidy: tab, range, severity, issue, fix
qa$pages                       # named list of PNG paths, one per PDF page
```

The files go to `tools::R_user_dir("r-googlesheets4", "cache")/visual_qa/<sheet id>/`
(the path is printed), so they still exist after `Rscript` exits. Pass
`out_dir =` to put them elsewhere; avoid `tempdir()`, which R deletes on exit.

1. Fix every **blocker** in `qa$findings` first. Each row carries a suggested
   helper call (`fix`).
2. `Read()` each PNG in `qa$pages` and score it with the checklist below.
3. Fix the **build script**, not the live sheet by hand, so the fix survives a rebuild.
4. Rebuild, run `visual_qa()` again, stop when no blocker or major remains.

Two layers, two truths: `audit_layout()` checks the on-screen grid
(deterministic). The PDF pages show the **print** layout (page size,
fit-to-width, margins, page breaks), so use them for print issues and as an
independent visual check of everything else. A defect that only appears in the
PDF is a print-setup problem (page breaks, scale), not a column-width problem.

## Severity

| Level | Meaning | Examples |
|---|---|---|
| blocker | Content is invisible or clipped | text cut off, `###` numbers, content in a hidden column, merge over a thin column |
| major | Looks broken | row shorter than its text, 30 px column holding content, low text/fill contrast, chart over data |
| minor | Polish | mixed number alignment, very wide column, inconsistent decimals |

## Checklist for each page image

1. **Truncation.** Any label ending mid-word (`Liqu`, `CLOSING` shown as `ING`)? Any `###`?
2. **Column proportion.** Label columns wide enough, numeric columns consistent, no giant empty columns, gutters intentionally narrow and empty.
3. **Row proportion.** Wrapped text fully visible, header rows taller than body rows, no cramped rows.
4. **Alignment.** Numbers right-aligned and sharing decimals; text left-aligned; headers aligned with the data below; titles anchored in the first visible column.
5. **Hierarchy.** The lead figure is the largest thing on the tab and answers the finding line under the title; section headings distinct from subtotals.
6. **Colour.** Colour only on data, status and inputs: one accent family, status colours only on rows at risk, a finance model's blue/black/green input, formula and link text ([finance-models.md](finance-models.md) §9) counts as data. No banded or zebra rows, no filled header bands, no tab colours except on tabs that hold inputs.
7. **Contrast.** Text readable on its fill (aim for 4.5:1), muted text still legible.
8. **Whitespace.** Consistent padding, no stray blank rows or columns, no content jammed against the edge.
9. **Charts.** Not overlapping cells, series visible (an empty "Add a series" placeholder means the source range is wrong or hidden), no rotated axis labels, no right-axis series. The title states a finding that is true for the data shown, or describes the chart.
10. **Errors.** No `#REF!`, `#N/A`, `#DIV/0!`, or formulas shown as text.
11. **Print.** Sensible page breaks, header rows repeated if the table spans pages, nothing split across pages that should stay together.

The design system behind items 5, 6 and 9 is in [design-principles.md](design-principles.md).

## Report format

One line per issue: `tab!range — what is wrong — fix`. End with a verdict:
**pass** (no blocker or major), **fix and re-run**, or **needs the user's decision**
(a design choice you should not make alone).

## Limits

- The width estimate is approximate (Arial-like metrics; Roboto, the default theme font, is about the same width). It is deliberately generous, so a flagged cell is worth a glance, but confirm on the page image before widening.
- A font outside Sheets' font menu renders differently in the PDF export. Roboto and Arial both embed.
- Report only what you saw. If you did not `Read()` a page image, say so; never describe it from the findings alone.
- The PDF export endpoint rate-limits bursts (HTTP 429); `visual_qa()` pauses between tabs and retries.
