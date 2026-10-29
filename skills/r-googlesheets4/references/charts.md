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
batch_format(ss, list(do.call(fmt_theme_colors, THEME_DEFAULT)), strict = TRUE)   # once per file
```

## Look: one hue, a finding for a title

Every chart takes `style = STYLE_CHART` (from `ds_tokens()`): the theme font, an
11 pt bold ink title on the left, a white background and a white border, so the
section rule above frames the chart instead of a box.

- **Leave `color` out.** The theme (`THEME_DEFAULT`) colours series 1 with the
  accent, then grey 949494, the dark accent 800, the light accent 400, and
  greys 3D3D3D and 767676. Put the series the tab is about first. Set `color` only to pin a
  token, such as `COL_ACCENT` on the main series or a `STATUS` mark when the
  categories are states. At most one accent family and one status hue per chart.
- **The title states a finding that is true for the data** ("Shopping and
  Health ran 50%+ over budget"), and the axis title carries the unit. A chart
  title cannot be a formula, so if the data can change, keep the claim true for
  any likely data or make the title descriptive ("Spending by category") and
  put the live finding in a cell above the chart.
- **No rotated axis labels.** Long category names go on a horizontal BAR chart;
  months go on a LINE chart or get short labels ("Jan", "Feb").
- **Left axis only.** The right axis cannot be titled or scaled (below), so a
  second scale becomes a second chart.
- **Legend:** `NO_LEGEND` for one series, `TOP_LEGEND` for two to four.
- **Lines:** the main series 3 px, comparisons 2 px, scenarios dotted (upside)
  and dashed (downside); no smoothing, no point markers.

## Basic chart: LINE / COLUMN / AREA / SCATTER / COMBO

```r
fmt_chart_basic(
  sheet_id     = sid,
  title        = "Revenue grew faster than costs, Jan to Jun",
  chart_type   = "LINE",
  domain_range = c(1, 7, 1, 1),                     # A1:A7  (row 1 = header)
  series_list  = list(
    list(range = c(1, 7, 2, 2), line = list(width = 3)),   # B1:B7, accent (theme slot 1)
    list(range = c(1, 7, 3, 3), line = list(width = 2))    # C1:C7, grey (theme slot 2)
  ),
  header_count = 1L,          # first cell of each range is the legend label
  anchor       = c(10L, 1L),  # row, col (1-based) of the top-left corner
  size         = c(600L, 371L),
  x_title      = "Month",     # BOTTOM axis title (optional)
  y_title      = "USD (thousand)",  # LEFT axis title (optional)
  legend       = "TOP_LEGEND",
  style        = STYLE_CHART
)
```

`stacked_type = "STACKED"` for stacked column/area, `"PERCENT_STACKED"`
for 100%-stacked.

Optional keys on each `series_list` entry:

| Key | Becomes | Example |
|-----|---------|---------|
| `color` | `colorStyle.rgbColor` | `COL_ACCENT`; leave it out to take the theme slot |
| `axis` | `targetAxis` | `"LEFT_AXIS"` (default), `"BOTTOM_AXIS"` (BAR) |
| `type` | per-series type, for COMBO | `"COLUMN"`, `"LINE"`, `"AREA"` |
| `line` | `lineStyle` | `list(width = 3, type = "MEDIUM_DASHED")` |
| `point` | `pointStyle` | `list(shape = "CIRCLE", size = 7)` |
| `label` | `dataLabel` | `list(type = "DATA", placement = "CENTER")` |
| `override` | `styleOverrides` | `list(list(index = 3L, color = COL_NEGATIVE))` |

`override` recolours single points (0-based, counted after the header), such
as the one bar over a limit. The indices are fixed when the chart is built, so
on bars that a picker or a SORT re-orders the colour stays on the old position.
There, split the data into two stacked series, "Within limit" (`COL_ACCENT`)
and "Over limit" (`COL_NEGATIVE`), each a formula, with
`stacked_type = "STACKED"`.

Things the API does that the helper cannot change:

- Series colour is RGB only. An alpha value is ignored.
- `pointStyle` takes `shape` (`CIRCLE`, `DIAMOND`, `SQUARE`, ...), never `type`.
- Axis titles exist for basic charts only. Charts also get default axis objects
  without titles, so reading `axis` back shows blank entries.
- The RIGHT axis cannot be titled, formatted or windowed: see "Chart style,
  offsets and axis windows".

### COMBO: bars with a dashed limit line

Set `chart_type = "COMBO"` and a `type` on every series. This is how to draw a
dashed limit or target line next to bars: a COLUMN chart rejects `line` on a
LINE series (HTTP 400). Write the limit as a column of the same value, named in
its header cell ("Budget"), and keep both series on the left axis:

```r
# Data!E1:E7 = "Budget", then 150 in every row
fmt_chart_basic(sid, "Revenue ended June above its 150 budget", "COMBO", c(1, 7, 1, 1),
  list(list(range = c(1, 7, 2, 2), color = COL_ACCENT, type = "COLUMN"),
       list(range = c(1, 7, 5, 5), color = hex_to_color("3D3D3D"), type = "LINE",
            line = list(width = 1, type = "MEDIUM_DASHED"))),
  legend = "TOP_LEGEND", anchor_sheet_id = dash, anchor = c(18L, 1L), style = STYLE_CHART)
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
    list(range = c(55, 55, 4, 16)),          # accent (theme slot 1)
    list(range = c(56, 56, 4, 16))           # grey (theme slot 2)
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
              list(list(range = c(1, 7, 2, 2))),
              anchor_sheet_id = dash, x_title = "USD (thousand)", style = STYLE_CHART)
```

A BAR chart is also the cure for long category names, which a COLUMN chart
rotates.

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
  connector_type   = "DOTTED",            # colours default to COL_POSITIVE, COL_NEGATIVE, COL_ACCENT
  subtotal_indices = c(0L, 5L),       # 0-based positions of the total rows
  subtotal_label   = "Total",         # legend entry for the total bars
  data_labels      = TRUE,            # value on every bar
  anchor_sheet_id  = dash, anchor = c(35L, 1L), size = c(600L, 371L),
  style            = STYLE_CHART
)
```

`positive_color`, `negative_color` and `subtotal_color` default to
`COL_POSITIVE` (1F7A47), `COL_NEGATIVE` (BB2D27) and `COL_ACCENT`, so a brand
swap carries through. Pass a colour list to change one.

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
              donut = TRUE,                                    # pie_hole 0.7 by default; donut = FALSE: plain pie
              legend = "NO_LEGEND",
              anchor_sheet_id = dash, anchor = c(35L, 8L), size = c(450L, 300L),
              style = STYLE_CHART)
```

Start both ranges on the first data row (the builder sets no header). Slice
colours come only from the spreadsheet theme accents (ACCENT1 to ACCENT6), for
the whole file; set them with `do.call(fmt_theme_colors, THEME_DEFAULT)`, not
per slice. Use at most five slices, sorted largest first with "Everything
else" last, so slice 1 is the accent. Put the legend in cells beside the ring
(a 16 px swatch cell filled with the slot colour, then name, value and share).
A breakdown by status (on track, at risk, late) is a 100% stacked bar with one
series per state in its `STATUS` mark, never a pie.

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
| `font` | `spec.fontName` | One family for the title, axes and legend, e.g. `"Roboto"` (`BRAND_FONT`). |
| `title_size` | `titleTextFormat.fontSize` | Points. |
| `title_bold` | `titleTextFormat.bold` | `TRUE` / `FALSE`. |
| `title_color` | `titleTextFormat.foregroundColorStyle` | Hex string (`"141414"`, `"#141414"`) or a `hex_to_color()` list. |
| `title_position` | `titleTextPosition` | `"LEFT"`, `"CENTER"` or `"RIGHT"`. |
| `background` | `backgroundColorStyle` | Hex or color list. |
| `border` | chart `border.colorStyle` | Hex or color list. Plain charts get a thin grey outline; the background colour hides it. |
| `axis_font_size` | each axis `format.fontSize` | Basic charts only. |
| `legend_font_size` | nothing | Accepted, ignored, warns. The API has no legend text size. |

`STYLE_CHART` is this list, rebuilt by `ds_tokens()` with your font:

```r
STYLE_CHART <- list(font = BRAND_FONT, title_size = 11, title_bold = TRUE,
                    title_color = "141414", title_position = "LEFT",
                    background = "FFFFFF", border = "FFFFFF", axis_font_size = 9)
STYLE <- STYLE_CHART

batch_format(ss, list(
  fmt_chart_basic(sid, "Revenue vs costs", "LINE", c(1, 7, 1, 1),
                  list(list(range = c(1, 7, 2, 2), line = list(width = 3)),
                       list(range = c(1, 7, 3, 3), line = list(width = 2))),
                  anchor_sheet_id = dash, anchor = c(3L, 2L),
                  x_title = "Month", y_title = "USD (thousand)",
                  y_min = 80, y_max = 200,       # fixed LEFT axis window
                  offset_x = 6L, offset_y = 4L,  # nudge inside the anchor cell
                  style = STYLE),
  fmt_chart_bar(sid, "Revenue by month", c(1, 7, 1, 1),
                list(list(range = c(1, 7, 2, 2))),
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

Share one `style` list (`STYLE_CHART`) across a dashboard so every chart matches. Checked live
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
- **No gridline colour or count.** Gridlines stay Sheets' light grey.
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
