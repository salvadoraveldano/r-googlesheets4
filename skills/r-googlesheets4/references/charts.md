# Charts

Native Google Sheets charts via `addChart` requests in `batchUpdate`.
Three spec families cover most needs: `basicChart` (LINE / COLUMN / BAR /
SCATTER / AREA / COMBO), `waterfallChart` and `pieChart` (pie and doughnut).

Helpers in `scripts/gs_charts.R`: `fmt_chart_basic()`, `fmt_chart_bar()`,
`fmt_chart_waterfall()`, `fmt_chart_pie()`. Each returns one `addChart`
request for `batch_format(ss, list(...), strict = TRUE)`. All four also take
`offset_x`, `offset_y` and `style` (fonts, title, background, border), and
`fmt_chart_basic()` takes axis windows: see "Chart style, offsets and axis
windows".

## Data tab and chart tab

Every builder takes two sheet ids:

- `sheet_id`: the tab the chart **reads its data from**.
- `anchor_sheet_id` (last argument, default `sheet_id`): the tab the chart
  **sits on**.

Leave `anchor_sheet_id` out for a chart beside its data. Pass it to read a
model tab and show the chart on a Summary or Dashboard tab:

```r
fmt_chart_basic(sid_model, "ARR", "LINE", domain_range, series_list,
                anchor = c(3L, 2L), anchor_sheet_id = sid_summary)
```

The anchor cell must lie inside the destination tab's grid. `sheet_write()`
trims a tab to its data, so a chart anchored below it fails with HTTP 400
("rowIndex[9] is after last row in grid[6]"). Grow the grid first with an
`updateSheetProperties` request on `gridProperties(rowCount,columnCount)`.

## Why charts fail silently: the audit imperative

Three failure modes return HTTP 200 OK but produce a broken chart in
the rendered tab:

1. **Source range overlaps a hidden column.** The chart renders the
   placeholder `"Add a series to start visualizing your data"`. The cells
   contain valid data; the chart engine refuses them. Seen live for basic,
   waterfall and pie charts. `audit_chart_sources()` from `gs_qa.R` catches
   most cases, not a partial series loss (see below).
2. **Per-scenario chart loop reads the wrong row.** Off-by-one in the
   offset map: all N charts source the same row, so they look identical
   and pass schema validation. Catch by reading back two scenarios'
   helper-block source cells and asserting the values differ.
3. **Series names default to "Series 1, 2, ...".** `BasicChartSeries` has
   no `name` field. Labels come from the first cell of `sourceRange`
   when the chart spec has `headerCount >= 1`.

After every chart build, run:

```r
audit_chart_sources(as.character(ss))          # every tab
audit_chart_sources(as.character(ss), sid)     # charts sitting on one tab
```

The audit checks each domain and series against the hidden columns of the tab
the data lives on, so a Summary chart fed by a model tab is judged on the
model tab. It also flags a basic or waterfall chart left with no series.
While columns are hidden, Sheets returns fewer series than the chart holds
(they all come back on unhide), and the one it returns is not always the one
that renders. A warning from the audit is reliable; silence is not proof, so
also compare the series count you read back with the number you built.

## Example data

The examples read a `Data` tab with a header row, months down column A and
one series per column:

```
   A      B        C       D
1  Month  Revenue  Costs   Profit
2  Jan    120      90      30
...
7  Jun    175      118     57
```

```r
sid  <- get_sheet_id(ss, "Data")
dash <- get_sheet_id(ss, "Dash")
BLUE <- hex_to_color("2457C5"); RED <- hex_to_color("C62828")
```

## Basic chart: LINE / COLUMN / AREA / SCATTER / COMBO

```r
fmt_chart_basic(
  sheet_id     = sid,
  title        = "Revenue vs costs",
  chart_type   = "LINE",
  domain_range = c(1, 7, 1, 1),                     # A1:A7  (row 1 = header)
  series_list  = list(
    list(range = c(1, 7, 2, 2), color = BLUE),      # B1:B7
    list(range = c(1, 7, 3, 3), color = RED)        # C1:C7
  ),
  header_count = 1L,          # first cell of each range is the legend label
  anchor       = c(10L, 1L),  # row, col (1-based) of the top-left corner
  size         = c(600L, 371L),
  x_title      = "Month",     # BOTTOM axis title (optional)
  y_title      = "USD (thousand)"   # LEFT axis title (optional)
)
```

`stacked_type = "STACKED"` for stacked column/area, `"PERCENT_STACKED"`
for 100%-stacked.

Optional keys on each `series_list` entry:

| Key | Becomes | Example |
|-----|---------|---------|
| `color` | `colorStyle.rgbColor` | `hex_to_color("2457C5")` |
| `axis` | `targetAxis` | `"RIGHT_AXIS"` |
| `type` | per-series type, for COMBO | `"COLUMN"`, `"LINE"`, `"AREA"` |
| `line` | `lineStyle` | `list(width = 3, type = "MEDIUM_DASHED")` |
| `point` | `pointStyle` | `list(shape = "CIRCLE", size = 7)` |
| `label` | `dataLabel` | `list(type = "DATA", placement = "CENTER")` |

Things the API does that the helper cannot change:

- Series colour is RGB only. An alpha value is ignored.
- `pointStyle` takes `shape` (`CIRCLE`, `DIAMOND`, `SQUARE`, ...), never `type`.
- Axis titles exist for basic charts only. Charts also get default axis objects
  without titles, so reading `axis` back shows blank entries.
- The RIGHT axis cannot be titled, formatted or windowed: see "Chart style,
  offsets and axis windows".

### COMBO

Set `chart_type = "COMBO"` and a `type` on every series. Put the line on the
right axis when its scale differs:

```r
fmt_chart_basic(sid, "Revenue and profit", "COMBO", c(1, 7, 1, 1),
  list(list(range = c(1, 7, 2, 2), color = BLUE, type = "COLUMN"),
       list(range = c(1, 7, 4, 4), color = hex_to_color("E0A100"),
            type = "LINE", axis = "RIGHT_AXIS")),
  anchor_sheet_id = dash, anchor = c(18L, 1L))
```

## Series labels via `headerCount = 1`

With one series per column (above), the label is the header cell at the top of
each range. With one series per row (months across columns), write a label
cell into the column **immediately left** of each series' data row and start
the `sourceRange` at that label column:

```r
# Labels in col D (left of monthly data in cols E:P)
write_cell(ss, TAB, 55L, 4L, "Series A")   # D55
write_cell(ss, TAB, 56L, 4L, "Series B")   # D56
flush_writes(ss)

fmt_chart_basic(
  sheet_id = sid, title = "Cash by category",
  chart_type = "COLUMN",
  domain_range = c(54, 54, 4, 16),         # months header row, D:P
  series_list = list(
    list(range = c(55, 55, 4, 16), color = BLUE),
    list(range = c(56, 56, 4, 16), color = hex_to_color("8AB4F8"))
  ),
  header_count = 1L,
  stacked_type = "STACKED"
)
```

## BAR (horizontal): must target BOTTOM_AXIS

Sheets rejects BAR charts whose series target `LEFT_AXIS`:

> Bar charts series may only target the BOTTOM_AXIS.

The default `targetAxis = "LEFT_AXIS"` works for LINE and COLUMN but
fails BAR. `fmt_chart_bar()` forces `BOTTOM_AXIS` automatically and passes
every other `fmt_chart_basic()` argument through (`anchor_sheet_id`,
`x_title`, `stacked_type`, ...). If you call `fmt_chart_basic()` with
`chart_type = "BAR"`, the default is also `BOTTOM_AXIS`; a series that sets
`axis` itself must keep it there.

```r
fmt_chart_bar(sid, "Revenue by month", c(1, 7, 1, 1),
              list(list(range = c(1, 7, 2, 2), color = BLUE)),
              anchor_sheet_id = dash, x_title = "USD (thousand)")
```

In a BAR chart the bottom axis carries the values and the left axis the
categories, so `x_title` titles the value axis and `y_title` the category axis.

## Waterfall

A waterfall has one category range and one value range. Both must cover the
same rows, and neither takes a header cell (the spec has no `headerCount`).
A 6-row category range with a 5-row value range rendered as a red error box
inside the chart.

Opening and Closing as full totals (the usual bridge):

```r
# Data!F2:F7 = Opening, Sales, Refunds, Costs, Other, Closing; G2:G7 = values
fmt_chart_waterfall(
  sheet_id         = sid,
  title            = "Cash bridge",
  domain_range     = c(2, 7, 6, 6),
  data_range       = c(2, 7, 7, 7),
  positive_color   = hex_to_color("2E8B57"),
  negative_color   = hex_to_color("C62828"),
  subtotal_color   = hex_to_color("163A85"),
  connector_type   = "DOTTED",
  subtotal_indices = c(0L, 5L),       # 0-based positions of the total rows
  subtotal_label   = "Total",         # legend entry for the total bars
  data_labels      = TRUE,            # value on every bar
  anchor_sheet_id  = dash, anchor = c(35L, 1L), size = c(600L, 371L)
)
```

`subtotal_indices` are 0-based positions inside the ranges. With the default
`subtotal_is_data = TRUE` those rows are the totals, drawn as full bars
from zero, and the row's own category label is shown. A `subtotal_labels`
entry has no effect in this mode: Sheets drops it from the stored spec.

To have the chart compute and INSERT a subtotal bar after a row instead, use
`subtotal_is_data = FALSE`. Then `subtotal_labels` names the inserted bar, and
Sheets also appends a final "Subtotal" bar. Hide it by patching the returned
request:

```r
req <- fmt_chart_waterfall(sid, "Bridge", c(2, 6, 6, 6), c(2, 6, 7, 7),
                           subtotal_indices = 2L, subtotal_labels = "Net after refunds",
                           subtotal_is_data = FALSE)
req$addChart$chart$spec$waterfallChart$series[[1]]$hideTrailingSubtotal <- TRUE
```

With no `subtotal_indices` the request carries no `customSubtotals` field.

Waterfall limits (API, not the helper):

- `connectorLineStyle` does NOT accept `colorStyle`, only `width` and `type`.
  Setting a colour returns HTTP 400. Colour the bars via
  `positive_color` / `negative_color` / `subtotal_color`.
- Waterfall charts cannot have axis titles and have no legend setting. The
  `legend` argument of `fmt_chart_waterfall()` is kept only for old calls; it
  is ignored and warns when you pass it.

## Pie and doughnut

```r
fmt_chart_pie(sid, "Spending", domain_range = c(2, 6, 9, 9),   # labels I2:I6
              data_range = c(2, 6, 10, 10),                    # values J2:J6
              donut = TRUE, pie_hole = 0.55,                   # donut = FALSE: plain pie
              legend = "RIGHT_LEGEND",
              anchor_sheet_id = dash, anchor = c(35L, 8L), size = c(450L, 300L))
```

Start both ranges on the first data row (the builder sets no header). Slice
colours come from the spreadsheet theme accents (ACCENT1 to ACCENT6); change them
with an `updateSpreadsheetProperties` theme request, not per slice.

## Chart style, offsets and axis windows

New trailing arguments, all optional. Leave them out and the request is
byte-for-byte what it was before.

| Argument | On | Does |
|----------|----|------|
| `offset_x`, `offset_y` | all four builders | Pixels to shift the chart inside its anchor cell (default 0). Lines a chart up with cells or KPI cards. |
| `style` | all four builders | Named list of look options (below). An unknown key stops with the allowed list. |
| `y_min`, `y_max` | `fmt_chart_basic()`, `fmt_chart_bar()` | Fixed ends of the LEFT axis. One end alone is fine; the other stays automatic. |
| `y2_title`, `y2_min`, `y2_max` | `fmt_chart_basic()`, `fmt_chart_bar()` | RIGHT axis title and ends. **Ignored by Sheets**, see below. |

`fmt_chart_bar()` hands all of these to `fmt_chart_basic()`. In a BAR chart the
left axis holds the categories, so `y_min`/`y_max` do nothing useful there.

`style` keys (each optional):

| Key | Becomes | Notes |
|-----|---------|-------|
| `font` | `spec.fontName` | One family for the title, axes and legend, e.g. `"Arial"`, `"Georgia"`. |
| `title_size` | `titleTextFormat.fontSize` | Points. |
| `title_bold` | `titleTextFormat.bold` | `TRUE` / `FALSE`. |
| `title_color` | `titleTextFormat.foregroundColorStyle` | Hex string (`"163A85"`, `"#163A85"`) or a `hex_to_color()` list. |
| `title_position` | `titleTextPosition` | `"LEFT"`, `"CENTER"` or `"RIGHT"`. |
| `background` | `backgroundColorStyle` | Hex or color list. |
| `border` | chart `border.colorStyle` | Hex or color list. Plain charts get a thin grey outline; the background colour hides it. |
| `axis_font_size` | each axis `format.fontSize` | Basic charts only. |
| `legend_font_size` | nothing | Accepted, ignored, warns. The API has no legend text size. |

```r
STYLE <- list(font = "Arial", title_size = 14, title_bold = TRUE,
              title_color = "163A85", title_position = "LEFT",
              background = "F7F9FC", border = "F7F9FC", axis_font_size = 10)

batch_format(ss, list(
  fmt_chart_basic(sid, "Revenue vs costs", "LINE", c(1, 7, 1, 1),
                  list(list(range = c(1, 7, 2, 2), color = BLUE),
                       list(range = c(1, 7, 3, 3), color = RED)),
                  anchor_sheet_id = dash, anchor = c(3L, 2L),
                  x_title = "Month", y_title = "USD (thousand)",
                  y_min = 80, y_max = 200,       # fixed LEFT axis window
                  offset_x = 6L, offset_y = 4L,  # nudge inside the anchor cell
                  style = STYLE),
  fmt_chart_bar(sid, "Revenue by month", c(1, 7, 1, 1),
                list(list(range = c(1, 7, 2, 2), color = BLUE)),
                anchor_sheet_id = dash, anchor = c(22L, 2L), x_title = "USD (thousand)",
                style = STYLE),
  fmt_chart_pie(sid, "Spending", c(2, 6, 9, 9), c(2, 6, 10, 10), donut = TRUE,
                anchor_sheet_id = dash, anchor = c(3L, 12L), style = STYLE),
  fmt_chart_waterfall(sid, "Cash bridge", c(2, 7, 6, 6), c(2, 7, 7, 7),
                      subtotal_indices = c(0L, 5L), data_labels = TRUE,
                      anchor_sheet_id = dash, anchor = c(22L, 12L),
                      offset_x = 6L, offset_y = 4L, style = STYLE)
), strict = TRUE)
```

Share one `style` list across a dashboard so every chart matches. Checked live
on all four builders: font, title format and position, background, border,
offsets and the left-axis window all read back from `sheets.charts` and render.

What the API does not give you (verified live, and why the helper cannot fix it):

- **The RIGHT axis ignores every setting.** A title, format or view window on
  `RIGHT_AXIS` is accepted with HTTP 200 and then dropped, in `addChart` and in
  `updateChartSpec`, for COMBO and LINE charts alike. The right axis keeps its
  automatic scale and has no title. `y2_title`, `y2_min` and `y2_max` are sent
  anyway (in case Google starts honoring them) and warn. Work around it: put
  the unit in the series' header cell so the legend names it, and scale the
  series in the sheet (a margin as 0 to 100 instead of 0 to 1) rather than on
  the axis. `y_min`/`y_max` on the LEFT axis work.
- **Axis `format` styles the axis TITLE, not the tick labels.** `axis_font_size`
  grows "Month" or "USD", not "Jan" or "150". It only reaches axes that carry a
  title or a window; pie and waterfall charts have no axes.
- **No legend text size.** `font` changes the legend's family. Its size stays
  at the Sheets default.
- **`font` is enough.** It sets `fontName`, and Sheets copies that family into
  the title and axis formats itself (read back, they show it), so the helper
  sets no per-part family.

After a style change, look at it: export the tab (`export_sheet_as_pdf()`) and
open the PNG. Reading `sheets.charts` back proves the field was stored, not
that it rendered.

## Helper-data placement: visible cols only

A very common chart bug: placing chart-helper data
(pre-aggregated waterfall labels + values, tornado driver labels,
variance-bridge totals) in the same hidden helper-col range used for
QUERY outputs and other dev scaffolding. The cells write fine, the
chart object creates fine, the chart renders blank.

**Rule:** chart-helper data lives in *visible* columns, placed past the
rightmost chart pixel extent.

```r
# BAD: helper in hidden col, so the chart renders the "Add a series" placeholder
COL_CH_LBL <- 27L  # AA, inside fmt_group_cols(sid, 27, 34, collapsed=TRUE)
COL_CH_VAL <- 28L  # AB, hidden, so the chart silently fails

# GOOD: helper in visible col, far right past chart anchors
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
2. **Source ranges** are not in hidden cols: `audit_chart_sources(ss_id)`, then
   compare each chart's series count with the number you built.
3. For per-scenario chart sets sourcing from helper blocks: read back
   two scenarios' helper cells and assert values differ.
4. **Helper data placement check**: confirm cols past the model's main
   content area are visible.
5. Look at it: export the tab to PDF (`export_sheet_as_pdf()`) or run
   `visual_qa()` and open the PNG. A schema-valid chart can still be empty.
