# Charts

Native Google Sheets charts via `addChart` requests in `batchUpdate`.
Two spec families cover most needs: `basicChart` (LINE / COLUMN / BAR /
SCATTER / AREA / COMBO) and `waterfallChart`.

Helpers: `fmt_chart_basic()`, `fmt_chart_bar()`, `fmt_chart_waterfall()`
in `scripts/gs_charts.R`.

## Why charts fail silently — the audit imperative

Three failure modes return HTTP 200 OK but produce a broken chart in
the rendered tab:

1. **Source range overlaps a hidden column.** Chart renders the
   placeholder `"Add a series to start visualizing your data"`. The cells
   contain valid data; the chart engine refuses them. Catch with
   `audit_chart_sources()` from `gs_qa.R`.
2. **Per-scenario chart loop reads the wrong row.** Off-by-one in the
   offset map → all N charts source the same row → identical-looking
   charts that pass schema validation. Catch by reading back two
   scenarios' helper-block source cells and asserting the values differ.
3. **Series names default to "Series 1, 2, …"**. `BasicChartSeries` has
   no `name` field — labels come from the first cell of `sourceRange`
   when chart spec `headerCount >= 1`.

After every chart-build, run:

```r
audit_chart_sources(as.character(ss), sid)
```

## Basic chart — LINE / COLUMN / AREA / SCATTER / COMBO

```r
fmt_chart_basic(
  sheet_id     = sid,
  title        = "Revenue by Month",
  chart_type   = "LINE",
  domain_range = c(R$months, R$months, COL_LBL, COL_M_LAST),
  series_list  = list(
    list(range = c(R$revenue,  R$revenue,  COL_LBL, COL_M_LAST),
         color = COL_BRAND),
    list(range = c(R$expenses, R$expenses, COL_LBL, COL_M_LAST),
         color = COL_RED_TEXT)
  ),
  header_count = 1L,         # ← legend labels from first cell
  anchor       = c(50L, 4L),
  size         = c(600L, 371L)
)
```

`stacked_type = "STACKED"` for stacked column/area, `"PERCENT_STACKED"`
for 100%-stacked.

## Series labels via `headerCount = 1`

Write a label cell into the column **immediately left** of each series'
data row. The chart's `sourceRange` starts at that label col, and
`headerCount = 1` tells Sheets the first cell is the legend label.

```r
# Labels in col D (left of monthly data in cols E:P)
write_cell(ss, TAB, R$series_a, COL_LBL, "Series A")  # D55
write_cell(ss, TAB, R$series_b,   COL_LBL, "Series B")    # D56
write_cell(ss, TAB, R$secondary,    COL_LBL, "Secondary")        # D57

# Chart sources start at COL_LBL, not col E
fmt_chart_basic(
  sheet_id = sid, title = "Cash by category",
  chart_type = "COLUMN",
  domain_range = c(R$months, R$months, COL_LBL, COL_M_LAST),
  series_list = list(
    list(range = c(R$series_a, R$series_a, COL_LBL, COL_M_LAST), color = COL_BRAND),
    list(range = c(R$series_b,   R$series_b,   COL_LBL, COL_M_LAST), color = hex_to_color("8AB4F8")),
    list(range = c(R$secondary,    R$secondary,       COL_LBL, COL_M_LAST), color = COL_BRAND_DEEP)
  ),
  header_count = 1L,
  stacked_type = "STACKED"
)
```

## BAR (horizontal) — must target BOTTOM_AXIS

Sheets rejects BAR charts whose series target `LEFT_AXIS`:

> Bar charts series may only target the BOTTOM_AXIS.

The default `targetAxis = "LEFT_AXIS"` works for LINE and COLUMN but
fails BAR. `fmt_chart_bar()` forces `BOTTOM_AXIS` automatically. If you
build the request manually, pass `axis = "BOTTOM_AXIS"` on every series:

```r
list(range = c(...), color = COL_BRAND, axis = "BOTTOM_AXIS")
```

## Waterfall

```r
fmt_chart_waterfall(
  sheet_id     = sid,
  title        = "Q1 Cash Flow",
  domain_range = c(R$wf_labels, R$wf_labels, COL_WF, COL_WF_LAST),
  data_range   = c(R$wf_values, R$wf_values, COL_WF, COL_WF_LAST),
  positive_color   = hex_to_color("2E8B57"),
  negative_color   = hex_to_color("C62828"),
  subtotal_color   = hex_to_color("4D4D4D"),
  connector_type   = "DOTTED",
  subtotal_indices = c(0L, 5L, 10L),    # which 0-based bars are subtotals
  anchor = c(50L, 4L), size = c(600L, 371L)
)
```

⚠️ `connectorLineStyle` does NOT accept `colorStyle` — only `width` and
`type`. Setting color returns HTTP 400. Color the bars via
`positiveColumnsStyle / negativeColumnsStyle / subtotalColumnsStyle`.

## Helper-data placement: visible cols only

A very common chart bug: placing chart-helper data
(pre-aggregated waterfall labels + values, tornado driver labels,
variance-bridge totals) in the same hidden helper-col range used for
QUERY outputs and other dev scaffolding. The cells write fine, the
chart object creates fine, the chart renders blank.

**Rule:** chart-helper data lives in *visible* columns, placed past the
rightmost chart pixel extent.

```r
# BAD — helper in hidden col → chart renders "Add a series" placeholder
COL_CH_LBL <- 27L  # AA, inside fmt_group_cols(sid, 27, 34, collapsed=TRUE)
COL_CH_VAL <- 28L  # AB, hidden — chart silently fails

# GOOD — helper in visible col, far right past chart anchors
COL_CH_LBL <- 47L  # AU
COL_CH_VAL <- 48L  # AV
```

If your charts anchor at col AL (38) with 480px width (~5 cols at 100px
each, ending ~col AP), put helper data at col AU (47) onward. Never
inside a `fmt_group_cols(..., collapsed = TRUE)` range.

## Pre-flight after build

After your `batchUpdate` returns:

1. **Chart count** matches expected (query `spreadsheets.get` with
   `fields = sheets.charts`).
2. **Source ranges** are not in hidden cols — `audit_chart_sources()`.
3. For per-scenario chart sets sourcing from helper blocks: read back
   two scenarios' helper cells and assert values differ.
4. **Helper data placement check**: confirm cols past the model's main
   content area are visible.
