# Design Principles

These apply to Google Sheets output the same way they apply to XLSX —
distilled from real shipped executive reports.

> **Wording:** use your organization's standard financial vocabulary for
> P&L labels and narrative cells (e.g. pick "gross profit" or "gross margin"
> once and keep it consistent) before finalizing user-facing text.

## 1. The 5-second rule

Key insight visible within 5 seconds of opening the tab. Subtitle, KPI
tiles, exec-summary band, the most important number rendered large.
Everything else is supporting.

## 2. Formulas over static values

Use SUMIFS / QUERY / INDEX-MATCH against raw-data tabs. The sheet
recalculates live when the user edits a driver cell or filters a tab.
Static values look fine on day one, lie on day twenty.

## 3. Consistent skeleton across tabs

Every department / category / scenario gets the same layout: same row
positions for the same labels, same column letters for the same months.
Lets users compare two tabs side-by-side without recalibrating.

## 4. Gray out, don't remove

Non-applicable sections (Revenue rows for cost-center departments) are
visually muted via `font_color = COL_GRAY_TEXT`. The reader sees that
the section exists but isn't relevant. Removing rows breaks the
skeleton from principle #3.

## 5. Don't make them do math

Pre-compute %, deltas, totals. The user shouldn't have to mentally
compute "OPEX is what % of Revenue?" from two cells; surface it as a
third cell with a `=IF(rev=0,"",opex/rev)  (or `f_safe_div()`)` formula.

## 6. Hide gridlines on presentation tabs

`fmt_gridlines(sid, show = FALSE)` on every output tab. Keep gridlines
on raw-data tabs (analysts use them).

## 7. Guard all division

Every `/` wrapped in `IF(denom=0,"",num/denom)` — use `f_safe_div()`
from `gs_formulas.R`. Never show `#DIV/0!` to a CFO.

## 8. Currency format: `$#,##0;($#,##0);"-"`

Parens for negatives (accounting convention), dash for zero. The
`NUMFMT_CURRENCY` constant in `gs_helpers.R` ships this pattern. For
red on negative, layer `fmt_cond_negative()` rather than baking
`[Red]` into the format.

## 9. Section headers — brand-blue fill with white bold text

Use `STYLE_SECTION_HEADER` overridden with the brand color (`COL_BRAND`
`#2457C5`, e.g. `STYLE_BRAND_SECTION_HEADER`), applied via
`write_section_header()`. Same color throughout a tab so the visual
rhythm carries the eye down the page.

## 10. Vertical alignment: MIDDLE on all cells

Apply `STYLE_BODY` (with `valign = "MIDDLE"`) to the full sheet range
as a global default. Top-aligned text mid-row makes financial tables
feel cramped.

## 11. Global defaults first, section overrides second

In `batchUpdate`, later requests override earlier ones for the same
cells. Set `STYLE_BODY` on all cells first, then apply section-specific
styles. This means you don't repeat baseline font/size everywhere.

## 12. Section borders: DOUBLE for primary, SOLID for secondary

DOUBLE brand-blue borders around the main P&L section. SOLID brand-blue
borders around the Allocation Schedule. Visual hierarchy guides the reader's eye.

## 13. Column grouping for helper areas

QUERY helper columns (e.g., U:Z) should be grouped and collapsed —
hidden from users but expandable for debugging. `fmt_group_cols()`.

## 14. Composable formatting functions

One pure function per visual section (`fmt_global`, `fmt_header`,
`fmt_pnl_section`), each returning `list(...)` of requests. Assemble
with `c()` and send in a single `batch_format()` call.

## 15. Number scaling matches the audience

| Scale       | Format                               | Audience                   |
|-------------|--------------------------------------|----------------------------|
| Millions    | `$#,##0,,"M"`                        | Board, exec summary        |
| Thousands   | `$#,##0,"K"`                         | Department head, summaries |
| Whole       | `$#,##0`                             | Analyst, raw data          |

Match the scale to where the user is reading. Don't put `$1.2M`
in a raw-data row; don't put `$1,234,567` in an exec summary header.

## 16. Time-period visual hierarchy

For multi-period summaries:

- **Decision month** (current focus): warm bg + bold + thicker borders.
- **Total column**: STYLE_TOTAL bold, light gray bg.
- **Future periods**: muted (gray bg, smaller font, gray font color).

Communicates priority without forcing the reader to count cols.

## 17. Reconciliation blocks

For any total stitched from multiple components (Q1 actuals + forecast),
include a Δ row that shows `total - canonical_source`. Should always be
0 — if not, the model has drifted and it's visible.
