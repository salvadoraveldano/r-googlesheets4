# Design system: Ledger

The default look of every sheet this skill builds. Ink on white paper with one
blue pen: structure comes from rules and type size, not from fills.

- **Grey and black are structure.** Rules separate blocks; size ranks them.
- **Blue means "you can type here" or "this is the main series".** Nothing else
  is blue.
- **Red, green and amber mean status.** Only status, and only where something
  is at risk.

Every token loads with `gs_helpers.R`; the presets and layout helpers load with
`gs_buffer.R`. `brand.R` is optional: it changes the accent and the font.

## Quick start

```r
source("scripts/gs_helpers.R"); source("scripts/gs_buffer.R")
b <- new_batch()
b$push(do.call(fmt_theme_colors, THEME_DEFAULT))       # font + chart colours, once per file
b$push(fmt_tab_base(sid, 40, 12, "dashboard", widths = c(224, 112, 112, 112, 112, 24, 96, 96, 96, 96)))
b$push(fmt_kpi_strip(sid, 6, 2:6, good = c("down", "up", "up", "up", "up"),
                     value_numfmt = NUMFMT_CURRENCY, delta_numfmt = NUMFMT_DELTA_PCT,
                     tol = 0.0005))                      # "+0.0%" stays grey
b$push(fmt_section(sid, 10, 2, 6, numeric_cols = 3:5, meta_col = 6))
b$push(fmt_table_body(sid, 12, 17, 2, 6, numeric_cols = 3:5, numfmt = NUMFMT_INT,
                      density = "dashboard", total_rows = 17))
b$push(fmt_status(sid, 12, 16, 6, 6, c(Over = "negative", Near = "warning")))
batch_format(ss, b$get(), strict = TRUE)
```

Text goes in with `write_cell()` / `write_block()` and one `flush_writes()`.
The helpers only format; none merges cells or writes values.

## Tokens

All text pairs reach 4.5:1 (WCAG); the repo's `scripts/offline-test.R` checks them.

**Text**

| Token | Hex | Use |
|---|---|---|
| `COL_INK` | 141414 | body, titles, figures (18.4:1 on white) |
| `COL_TEXT_2` | 474747 | the finding line, table headers |
| `COL_TEXT_3` | 666666 | labels, notes, units, "fine" states (5.7:1) |
| disabled | `COL_TEXT_3` + italic on `COL_SURFACE` | `STYLE_GRAYED_OUT` (5.3:1) |

**Rules and surfaces** (borders are always `SOLID`, the thinnest style)

| Token | Hex | Use |
|---|---|---|
| `COL_RULE_INK` / `BORDER_INK` | 141414 | above each block and above totals |
| `BORDER_DOUBLE` | 141414 | under totals |
| `COL_SEP_STRONG` / `BORDER_STRONG` | 999999 | under table headers, above subtotals |
| `COL_SEP_SUBTLE` / `BORDER_SUBTLE` | E6E6E6 | between body rows |
| `COL_SEP_MEDIUM` | CCCCCC | a box that is not an input |
| `COL_GROUND` | FFFFFF | the page. No ground fill: PDFs print white |
| `COL_SURFACE` | F5F5F5 | the total column, disabled cells |
| `COL_RAISED` | EFEFEF | the selected row or column (with bold) |

**Accent** (from `ds_tokens()`, default 2457C5)

| Token | Default | Use |
|---|---|---|
| `COL_ACCENT` (= `COL_BRAND`) | 2457C5 | the main chart series, the control's box |
| `COL_ACCENT_100` / `_200` | E9EEF9 / C8D5F0 | scale stops |
| `COL_ACCENT_400` | 7594D7 | a lighter accent series |
| `COL_ACCENT_700` (= `COL_BRAND_DEEP`) | 1C449A | links |
| `COL_ACCENT_800` | 14306C | a second accent series |

**Inputs and the finance colour code** (fixed: they do not follow the accent,
so "blue = editable" survives a brand swap)

| Token | Hex | Use |
|---|---|---|
| `STYLE_INPUT` | 2457C5 on E9EEF9 (5.6:1) | every typed-in cell, one look |
| `COL_FORMULA_FG` | 141414 | same-tab formulas |
| `COL_LINK_FG` | 1D7343 | formulas that pull from another tab |

**Status** (`STATUS$<state>$fill`, `$ink`, `$mark`)

| State | Fill | Ink | Mark |
|---|---|---|---|
| positive | E3F2E8 | 17603A | 1F7A47 (`COL_POSITIVE`, text-safe) |
| negative | FBE9E7 | 9B2420 | BB2D27 (`COL_NEGATIVE`, text-safe) |
| warning | FCF0D9 | 7A4A00 | B8740A (`COL_WARNING`, bars and lines only) |
| info | E3F1F3 | 0D5562 | 16788A (`COL_INFO`) |
| neutral | EFEFEF | 3D3D3D | 8C8C8C |

Chips use fill + ink. Deltas, bars and lines use the mark. Info is petrol, not
blue, so it never reads as an input.

**Charts and scales**

- `CHART_PALETTE` (= theme ACCENT1-6): accent, 949494, accent-800, accent-400,
  3D3D3D, 767676. The accent goes on the series the tab is about, grey on the
  comparisons. Neighbouring slots alternate dark and light.
- `SCALE_DIV` (blue → white → red, good low and bad high; the default of
  `fmt_cond_color_scale()`), `SCALE_HEAT` (white → amber → red, higher is
  worse), `SCALE_SEQ` (white → accent; never on a tab with inputs). Keep the
  text in scaled cells in ink.

## Type

Font: Roboto, set once through the theme (`THEME_DEFAULT$font_family`). It
renders in the grid, the charts and the PDF export, and its digits are equal
width, so columns of figures line up. No preset names a font, so Arial is a
one-line change in `brand.R` and nothing else moves. Inter, Geist and DM Sans
have proportional digits, and Sheets cannot switch on tabular figures.

| Role | pt | Bold | Colour | Preset |
|---|---|---|---|---|
| Tab title | 20 | yes | ink | `STYLE_TITLE` |
| Finding (one sentence) | 11 | no | text 2 | `STYLE_FINDING` |
| KPI lead value | 28 | no | ink | `fmt_kpi_strip()` |
| KPI other values | 18 | no | ink | `fmt_kpi_strip()` |
| Section heading | 12 | yes | ink | `STYLE_SECTION_HEADER` |
| Body, table cells | 10 | no | ink | `STYLE_BODY` |
| Table header | 9 | yes | text 2 | `STYLE_HEADER` |
| Label, delta, note, meta | 9 | no | text 3 | `STYLE_NOTE` |
| Chip, badge | 9 | yes | status ink | `STYLE_CHIP` |
| Chart title / axis title | 11 / 9 | yes / no | ink | `STYLE_CHART` |

Bold is the only weight Sheets has. Use it for titles, headings, table headers,
subtotals and totals, chips and the control. Never bold body figures or KPI
values: size carries them. Sentence case everywhere; no capitals, no italics
except the disabled role.

## Space

- **Gutters**: column A is 16 px, and so is the column after the last content
  column. Side-by-side blocks are split by one 24 px column.
- **Dashboard grid**: A 16 | B 224 (lead KPI, labels) | C-F 4 × 112 | G 24 |
  H-K 4 × 96 (charts) | L 16 = 1112 px, which fits a laptop screen and prints
  A4 landscape with `fitw`.
- **Model grid**: A 16 | B 240 (label) | C 64 (unit, muted) | periods 88 each |
  total 96 on `COL_SURFACE` | 16.
- **Rows** (px): title 36, finding 22, meta 18, spacers 12; KPI 20 / 44 / 20;
  section heading 30; table header 26; body 24 (model) or 28 (dashboard);
  total 28; data tabs keep the default.
- **Numbers never overflow into the next cell**, so size every numeric column
  for its widest formatted value ("$83,236" at 28 pt needs about 140 px).
- **No merges** in new layouts: text overflows into the empty cells to its
  right. A control or a badge is ONE cell wide enough for its text, because a
  centred value over two unmerged cells is clipped on both sides.
- **Gridlines** off on dashboards and models, on for data and log tabs.
- **Freeze only tabs that are one table.** Frozen rows repeat on every printed
  page, over a chart or a second block lower down.

## Components

| Component | Recipe | Helper |
|---|---|---|
| Title block | title (B2), finding (B3), meta line (B4: "Sample data · from Transactions rows 2-215 · USD · built 2026-10-23"), spacers | `fmt_tab_base()` |
| Finding | one sentence that answers the tab's question, with numbers; on a live model a formula (`="ARR reaches "&TEXT(x,"$0.0,,""M""")&" by month 24"`) so it cannot go stale | `STYLE_FINDING` |
| KPI strip | label / value / delta rows; the lead figure (the one the finding is about) at 28 pt, up to four others at 18 pt; no tiles, fills, top bars or sparklines; deltas coloured by each KPI's good direction; one note row naming the comparison ("Changes are vs August 2026"); a change within `tol` stays grey | `fmt_kpi_strip()` |
| Section | heading over an ink rule; header row with a #999 rule under it; numeric headers right-aligned | `fmt_section()` |
| Table | faint row rules, no zebra, numbers right-aligned; a missing value is a grey "-", a real zero is printed | `fmt_table_body()` |
| Subtotal / total | bold with a #999 rule above / bold with an ink rule above and a double rule below; the total column on `COL_SURFACE` | `fmt_table_body()` |
| Input | blue on pale blue, one look everywhere; an override of a formula gets the same look plus a note "[override]" | `STYLE_INPUT` |
| Control (one per tab) | `STYLE_CONTROL` in one cell, a `SOLID_MEDIUM` `COL_ACCENT` box, a dropdown, a 9 pt grey label to its left | `STYLE_CONTROL` + `fmt_borders()` + `fmt_dropdown()` |
| Status | the word names the state; pale fill + dark ink; "fine" states stay grey text | `fmt_status()` |
| Check badge | one cell: `=IF(ABS(diff)<=check_tol,"✓ Ties: 14 of 14 checks pass","✕ Off by "&TEXT(diff,"$#,##0"))`; the glyph carries the meaning without colour | `fmt_status(op = "starts_with")` |
| Colour key (models) | three cells styled exactly like what they explain: "Input", "Formula", "From another tab" | `STYLE_INPUT`, `COL_LINK_FG` |
| Selected row | `fmt_cond_formula(bg_color = COL_RAISED, bold = TRUE)` driven by the control; never blue | |
| Notes | "Source:" or "Note:" and the units, 9 pt grey | `STYLE_NOTE` |
| Tab colour | none, except tabs that hold inputs (blue = you type here) | `fmt_tab_base(inputs = TRUE)` |

## Charts

- `style = STYLE_CHART` on every chart: Roboto, an 11 pt bold title on the
  left, a white background and a white border (the section rule frames it).
- **The title states the finding** ("Shopping and Health ran 50%+ over budget");
  the axis title carries the unit.
- **One hue.** Leave `color` out and the theme gives the first series the accent
  and the rest greys. A status mark replaces grey only when the categories are
  states. At most one accent family plus one status hue per chart.
- **Line**: main series 3 px; comparisons 2 px; scenarios dotted (upside) and
  dashed (downside); no smoothing, no point markers.
- **Bars**: one colour; over-limit bars through a series `override` in
  `COL_NEGATIVE`; a limit line needs `chart_type = "COMBO"` (a COLUMN chart
  rejects a dashed LINE series) with a 1 px `MEDIUM_DASHED` series in 3D3D3D.
- **Pie / doughnut**: `pie_hole = 0.7` (the default), at most five slices
  sorted largest first, "Everything else" last. Slice colours come only from
  the theme. Status breakdowns are a 100% stacked bar, never a pie.
- **Legend**: none for one series, `TOP_LEGEND` for two to four.
- **Axis numbers take the source cells' format**, so a format that prints zero
  as "-" puts a "-" on the axis. Give chart source columns a format with `$0`
  for zero.
- The API has no setting for gridline colour or legend text size; leave them.

## Change the accent or the font

Edit two lines in `scripts/brand.R` and source it after `gs_buffer.R`:

```r
ACCENT_HEX <- "7B3F98"   # your brand colour
BRAND_FONT <- "Roboto"
```

`ds_tokens()` rebuilds the ladder, darkening each step until it reads, and
stops if the colour is under 3:1 on white. It warns when the hue sits next to
a status colour (a teal reads as "info", a rust as "negative"). Inputs stay
blue. Send `do.call(fmt_theme_colors, THEME_DEFAULT)` again so the file's
theme follows.

## Principles

1. **The 5-second rule.** The tab's question is answered by the biggest thing on
   it, read first: title, finding, lead figure, then the evidence.
2. **Formulas over static values.** SUMIFS / QUERY / INDEX-MATCH against raw-data
   tabs, so the sheet recalculates when a driver or a picker changes.
3. **One skeleton across tabs.** Same rows for the same labels, same columns for
   the same months, so two tabs compare side by side.
4. **Grey out, don't remove.** A section that does not apply keeps its rows in
   `STYLE_GRAYED_OUT`, so the skeleton holds.
5. **Don't make them do math.** Pre-compute shares, deltas and totals.
6. **Guard every division**: `f_safe_div()`. Never show `#DIV/0!`.
7. **Currency**: `NUMFMT_CURRENCY` (`$#,##0;($#,##0);"-"`): parentheses for
   negatives, a dash for zero. Colour negatives on output tabs only, with
   `fmt_cond_negative()`; model grids carry parentheses and no red.
8. **Scale to the reader**: `NUMFMT_CURRENCY_M1` ($3.5M) for a board,
   `NUMFMT_CURRENCY_K` for a department head, whole dollars for an analyst.
   (`NUMFMT_CURRENCY_M` rounds $3.5M to "$4M".)
9. **Global defaults first.** `STYLE_BODY` over the whole tab, then section
   styles; later requests win in one batch.
10. **Composable formatting.** One function per section returning requests,
    combined with `c()` and sent in one `batch_format()`.
11. **Helper columns hidden, not deleted**: `fmt_group_cols()`.
12. **Time periods**: the decision month in `COL_RAISED` + bold, the total column
    on `COL_SURFACE`, future months in `COL_TEXT_3`.
13. **Reconcile.** A total stitched from parts gets a Δ row against its source;
    it should read 0, and the Checks badge says so.

> **Wording:** use your organisation's financial vocabulary for P&L labels
> ("gross profit" or "gross margin", once) before finalising text.

## Don't

Saturated fills behind headers, tinted KPI tiles with coloured top bars,
sparklines on KPIs, uppercase letter-spaced labels, a different tab colour on
every tab, rainbow charts, a status colour on a zero change, red on every
negative in a model, yellow input fills, zebra rows, merged banners, more than
one accent family.

## Credit

Design tokens inspired by the open-source Salt Design System
(github.com/jpmorganchase/salt-ds, Apache-2.0): its black-at-opacity
separators, status tint pattern and container levels. No Salt code, token
files, J.P. Morgan colours or fonts are used. Not affiliated with or endorsed
by JPMorgan Chase & Co. The finance colour code is industry practice; the
no-merge rule comes from the FAST Standard.
