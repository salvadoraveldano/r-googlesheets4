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
5. **Hierarchy.** The key figure is visible in 5 seconds (title, subtitle, KPIs); section headers distinct from subtotals; one accent color, semantic colors only on data.
6. **Contrast.** Text readable on its fill (aim for 4.5:1), muted text still legible.
7. **Whitespace.** Consistent padding, no stray blank rows or columns, no content jammed against the edge.
8. **Charts.** Not overlapping cells, legible axis labels, series visible (an empty "Add a series" placeholder means the source range is wrong or hidden).
9. **Errors.** No `#REF!`, `#N/A`, `#DIV/0!`, or formulas shown as text.
10. **Print.** Sensible page breaks, header rows repeated if the table spans pages, nothing split across pages that should stay together.

## Report format

One line per issue: `tab!range — what is wrong — fix`. End with a verdict:
**pass** (no blocker or major), **fix and re-run**, or **needs the user's decision**
(a design choice you should not make alone).

## Limits

- The width estimate is approximate (Arial-like fonts). It is deliberately generous, so a flagged cell is worth a glance, but confirm on the page image before widening.
- Fonts that are not web-safe render differently in the PDF export.
- Report only what you saw. If you did not `Read()` a page image, say so; never describe it from the findings alone.
- The PDF export endpoint rate-limits bursts (HTTP 429); `visual_qa()` pauses between tabs and retries.
