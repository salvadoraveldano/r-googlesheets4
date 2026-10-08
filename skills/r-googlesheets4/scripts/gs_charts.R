# =============================================================================
# gs_charts.R — Native Google Sheets charts via addChart batchUpdate
# =============================================================================
#
# Three spec families cover most needs:
#   * basicChart    — LINE, COLUMN, BAR, SCATTER, AREA, COMBO (with STACKED)
#   * waterfallChart
#   * pieChart      — pie and doughnut (`fmt_chart_pie()`)
#
# Every builder takes `sheet_id` (the tab the DATA lives on) and a trailing
# `anchor_sheet_id` (the tab the chart SITS on; default = `sheet_id`). Read from
# a model tab and show on a Summary tab by passing both.
#
# Critical pitfalls all helpers below guard against:
#   1. Helper / source data MUST live in visible columns. A chart whose
#      sourceRange overlaps a hidden col silently renders the placeholder
#      ("Add a series to start visualizing your data") with no error response.
#      Audit with `audit_chart_sources()` from gs_qa.R.
#   2. BAR (horizontal) series must target BOTTOM_AXIS, not the default
#      LEFT_AXIS — the entire batchUpdate fails HTTP 400 otherwise.
#   3. Series legend names come from the first cell of the sourceRange ONLY
#      when the chart spec has `headerCount >= 1`.
#   4. waterfall.connectorLineStyle does NOT accept colorStyle — only width
#      and type. Color the bars via positive/negative/subtotalColumnsStyle.
#   5. Source data goes in as ChartData: list(sourceRange = list(sources = ...)).
#      Leaving out the `sourceRange` wrapper is rejected with HTTP 400
#      'Unknown name "sources"'; `.source_range()` below builds the right shape.
#   6. Series colors are RGB only; an alpha value is ignored. A series'
#      `pointStyle` takes `shape` (CIRCLE, DIAMOND, ...), never `type`.
#   7. Waterfall charts have no legend setting and no axis titles.
#   8. Look (font, title format, background, border) is the `style` list, applied
#      by `.chart_style()`. `font` is the chart's fontName, which Sheets applies to
#      the title, axes and legend. The API has no legend text SIZE, and an axis
#      `format` styles the axis TITLE, not the tick labels.
#   9. Sheets silently DROPS RIGHT_AXIS settings (title, format, view window):
#      `y2_title`/`y2_min`/`y2_max` are sent but the right axis stays automatic.
#      LEFT and BOTTOM axis settings work. Checked live 2026-10 (addChart and
#      updateChartSpec, COMBO and LINE). Re-read `sheets.charts` before trusting it.
#
# Sourcing order: gs_helpers.R first.
# =============================================================================

if (!exists("grid_range")) stop("Source gs_helpers.R before gs_charts.R")

# ── Internal: build ChartData from c(start_row, end_row, start_col, end_col).
# ChartData needs the `sourceRange` wrapper — a bare list(sources = ...) is HTTP 400.
.source_range <- function(sheet_id, range4) {
  list(sourceRange = list(sources = list(grid_range(sheet_id, range4[1L], range4[2L],
                                                    range4[3L], range4[4L]))))
}

# ── Internal: anchor an embedded chart at a specific cell
.embedded_object_position <- function(sheet_id, anchor_row, anchor_col,
                                      width_px = 600L, height_px = 371L,
                                      offset_x = 0L, offset_y = 0L) {
  list(overlayPosition = list(
    anchorCell = list(
      sheetId    = sheet_id,
      rowIndex   = anchor_row - 1L,
      columnIndex = anchor_col - 1L
    ),
    offsetXPixels = offset_x,
    offsetYPixels = offset_y,
    widthPixels   = width_px,
    heightPixels  = height_px
  ))
}

# ── Internal: one axis entry (title + EXPLICIT view window), NULL when nothing to say
.axis_spec <- function(position, title = NULL, lo = NULL, hi = NULL) {
  if (!all(vapply(list(lo, hi), function(v) is.null(v) || (is.numeric(v) && length(v) == 1L), NA)))
    stop("[fmt_chart_basic] axis min/max must be single numbers (", position, ").", call. = FALSE)
  ax <- list(position = position)
  if (!is.null(title)) ax$title <- title
  if (!is.null(lo) || !is.null(hi)) {
    w <- list(viewWindowMode = "EXPLICIT")   # an unset end falls back to Sheets' automatic value
    if (!is.null(lo)) w$viewWindowMin <- lo
    if (!is.null(hi)) w$viewWindowMax <- hi
    ax$viewWindowOptions <- w
  }
  if (length(ax) > 1L) ax
}

# ── Internal: chart look from the `style` list, applied to a built addChart request.
# NULL style = request returned untouched. Keys documented on fmt_chart_basic().
.chart_style_keys <- c("font", "title_size", "title_bold", "title_color", "title_position",
                       "background", "border", "axis_font_size", "legend_font_size")

.style_color <- function(x, key) {
  if (is.character(x) && length(x) == 1L && grepl("^#?[0-9A-Fa-f]{6}$", x)) return(hex_to_color(x))
  if (is.list(x) && length(x) && all(names(x) %in% c("red", "green", "blue", "alpha"))) return(x)
  stop("[chart style] `", key, "` must be a hex string like \"2457C5\" or a color list from hex_to_color().",
       call. = FALSE)
}

.chart_style <- function(req, style) {
  if (is.null(style)) return(req)
  if (!is.list(style) || (length(style) && is.null(names(style))))
    stop("[chart style] `style` must be a named list, e.g. list(font = \"Arial\", title_size = 12).", call. = FALSE)
  bad <- setdiff(names(style), .chart_style_keys)
  if (length(bad))
    stop("[chart style] unknown key(s): ", paste0("'", bad, "'", collapse = ", "), ". Allowed: ",
         paste(.chart_style_keys, collapse = ", "), ".", call. = FALSE)
  if (!is.null(style$legend_font_size))
    warning("[chart style] `legend_font_size` is ignored: the Sheets API has no legend text size. ",
            "`font` sets the legend font family.", call. = FALSE)

  ch <- req$addChart$chart
  sp <- ch$spec
  if (!is.null(style$font)) {
    if (!(is.character(style$font) && length(style$font) == 1L))
      stop("[chart style] `font` must be one font family name, e.g. \"Arial\".", call. = FALSE)
    sp$fontName <- style$font                       # default for ALL chart text: title, axes, legend
  }
  tf <- list()   # no fontFamily here: Sheets fills the title's family in from fontName
  if (!is.null(style$title_size))  tf$fontSize   <- as.integer(style$title_size)
  if (!is.null(style$title_bold))  tf$bold       <- isTRUE(style$title_bold)
  if (!is.null(style$title_color)) tf$foregroundColorStyle <- list(rgbColor = .style_color(style$title_color, "title_color"))
  if (length(tf)) sp$titleTextFormat <- tf
  if (!is.null(style$title_position)) {
    pos <- toupper(style$title_position)
    if (!(length(pos) == 1L && pos %in% c("LEFT", "CENTER", "RIGHT")))
      stop("[chart style] `title_position` must be \"LEFT\", \"CENTER\" or \"RIGHT\".", call. = FALSE)
    sp$titleTextPosition <- list(horizontalAlignment = pos)
  }
  if (!is.null(style$background))
    sp$backgroundColorStyle <- list(rgbColor = .style_color(style$background, "background"))
  if (!is.null(style$border))     # EmbeddedChart.border sits beside spec; plain charts get a thin grey outline
    ch$border <- list(colorStyle = list(rgbColor = .style_color(style$border, "border")))

  b <- sp$basicChart   # pie and waterfall charts have no axes, so axis_font_size is a no-op there
  if (!is.null(b) && length(b$axis) && !is.null(style$axis_font_size)) {
    b$axis <- lapply(b$axis, function(a) {
      a$format <- list(fontSize = as.integer(style$axis_font_size))
      a
    })
    sp$basicChart <- b
  }
  ch$spec <- sp
  req$addChart$chart <- ch
  req
}

# ── Basic chart -------------------------------------------------------------

#' Build an `addChart` request for a basic chart (LINE / COLUMN / BAR / AREA /
#' SCATTER / COMBO).
#'
#' @param sheet_id      sheetId the chart reads its DATA from
#' @param title         chart title
#' @param chart_type    "LINE" | "COLUMN" | "BAR" | "AREA" | "SCATTER" | "COMBO"
#' @param domain_range  c(start_row, end_row, start_col, end_col) — 1-based, inclusive
#' @param series_list   list of per-series specs:
#'                      list(range = c(...), color = list(red,green,blue),
#'                           axis = "LEFT_AXIS"|"RIGHT_AXIS"|"BOTTOM_AXIS",
#'                           type = "LINE"|"COLUMN"|"AREA" (for COMBO),
#'                           line = list(width = 3, type = "MEDIUM_DASHED"),
#'                           point = list(shape = "CIRCLE", size = 7),
#'                           label = list(type = "DATA", placement = "ABOVE"))
#'                      Only `range` is required. `color` is RGB; alpha is ignored.
#'                      `point` takes `shape`, not `type`.
#' @param header_count  1L when first cell of each range is the legend label
#' @param stacked_type  NULL | "STACKED" | "PERCENT_STACKED"
#' @param anchor        c(row, col) — 1-based anchor for the chart's top-left
#' @param size          c(width_px, height_px)
#' @param legend        "BOTTOM_LEGEND" | "LEFT_LEGEND" | "RIGHT_LEGEND" |
#'                      "TOP_LEGEND" | "NO_LEGEND"
#' @param anchor_sheet_id sheetId of the tab the chart SITS on (default
#'                      `sheet_id`). Set it to read data from one tab and show
#'                      the chart on another (Summary / Dashboard pattern).
#' @param x_title       NULL | text for the BOTTOM axis. In a BAR chart the
#'                      bottom axis is the VALUE axis.
#' @param y_title       NULL | text for the LEFT axis (the category axis in BAR)
#' @param y_min,y_max   NULL | fixed ends of the LEFT axis (numbers). One end alone
#'                      is fine; the other stays automatic. In BAR the left axis
#'                      is the category axis, so these do nothing useful there.
#' @param y2_title,y2_min,y2_max  NULL | title and fixed ends for the RIGHT axis.
#'                      NOT EFFECTIVE: the Sheets API drops every RIGHT_AXIS
#'                      setting (verified live), so using them warns and the right
#'                      axis stays automatic and untitled. Name the series in its
#'                      header cell (the legend shows it). Sent anyway, in case
#'                      Google starts honoring them.
#' @param offset_x,offset_y pixels to shift the chart inside its anchor cell
#'                      (default 0). Lines a chart up with cells or KPI cards.
#' @param style         NULL | named list of look options, all optional; an unknown
#'                      key stops. Works on every `fmt_chart_*` builder.
#'                      `font` (family for title, axes and legend), `title_size`,
#'                      `title_bold`, `title_color` (hex or color list),
#'                      `title_position` ("LEFT" | "CENTER" | "RIGHT"),
#'                      `background` (hex or color list), `border` (hex or color
#'                      list), `axis_font_size` (axis TITLE size, left and bottom
#'                      axes that carry a title; basic charts only),
#'                      `legend_font_size` (accepted but ignored with a warning:
#'                      the API has no legend text size).
#'                      `fmt_chart_bar()` takes all of these through `...`.
fmt_chart_basic <- function(sheet_id, title, chart_type,
                            domain_range, series_list,
                            header_count = 1L,
                            stacked_type = NULL,
                            anchor = c(1L, 1L),
                            size = c(600L, 371L),
                            legend = "BOTTOM_LEGEND",
                            anchor_sheet_id = sheet_id,
                            x_title = NULL,
                            y_title = NULL,
                            y2_title = NULL,
                            y_min = NULL, y_max = NULL,
                            y2_min = NULL, y2_max = NULL,
                            offset_x = 0L, offset_y = 0L,
                            style = NULL) {
  if (!is.null(y2_title) || !is.null(y2_min) || !is.null(y2_max))
    warning("fmt_chart_basic(): y2_title / y2_min / y2_max are sent, but the Sheets API drops RIGHT_AXIS ",
            "settings (checked live 2026-10), so the right axis keeps its automatic scale and no title. ",
            "Name the series in its header cell instead.", call. = FALSE)
  series <- lapply(series_list, function(s) {
    target_axis <- s$axis %||%
      (if (chart_type == "BAR") "BOTTOM_AXIS" else "LEFT_AXIS")
    out <- list(
      series = .source_range(sheet_id, s$range),
      targetAxis = target_axis
    )
    if (!is.null(s$color)) out$colorStyle <- list(rgbColor = s$color)
    if (!is.null(s$type)) out$type <- s$type
    if (!is.null(s$line)) out$lineStyle <- s$line
    if (!is.null(s$point)) out$pointStyle <- s$point
    if (!is.null(s$label)) out$dataLabel <- s$label
    out
  })

  basic <- list(
    chartType = chart_type,
    legendPosition = legend,
    headerCount = header_count,
    domains = list(list(domain = .source_range(sheet_id, domain_range))),
    series = series
  )
  if (!is.null(stacked_type)) basic$stackedType <- stacked_type
  axes <- Filter(Negate(is.null), list(.axis_spec("BOTTOM_AXIS", x_title),
                                       .axis_spec("LEFT_AXIS",   y_title,  y_min,  y_max),
                                       .axis_spec("RIGHT_AXIS",  y2_title, y2_min, y2_max)))
  if (length(axes)) basic$axis <- axes

  .chart_style(list(addChart = list(chart = list(
    spec = list(title = title, basicChart = basic),
    position = .embedded_object_position(anchor_sheet_id, anchor[1L], anchor[2L],
                                         size[1L], size[2L],
                                         as.integer(offset_x), as.integer(offset_y))
  ))), style)
}

# ── BAR (horizontal) — convenience wrapper that defaults BOTTOM_AXIS --------

#' Horizontal BAR chart. Forces BOTTOM_AXIS on every series unless overridden
#' (Sheets rejects BAR series targeting LEFT_AXIS with HTTP 400). Takes every
#' other `fmt_chart_basic()` argument through `...` (`anchor_sheet_id`,
#' `x_title`, `y_title`, `stacked_type`, `offset_x`, `offset_y`, `style`, ...).
fmt_chart_bar <- function(sheet_id, title, domain_range, series_list, ...) {
  series_list <- lapply(series_list, function(s) {
    if (is.null(s$axis)) s$axis <- "BOTTOM_AXIS"
    s
  })
  fmt_chart_basic(sheet_id, title, "BAR",
                  domain_range = domain_range, series_list = series_list, ...)
}

# ── Waterfall chart ---------------------------------------------------------

#' Build an `addChart` request for a waterfall chart.
#'
#' Subtotals: list the 0-based positions (within the domain/data ranges) of rows
#' that are totals in `subtotal_indices`, e.g. Opening and Closing balance of
#' a 6-row bridge: `subtotal_indices = c(0L, 5L)`. With the default
#' `subtotal_is_data = TRUE` those rows are drawn as full totals. With FALSE the
#' chart instead INSERTS an extra computed subtotal bar after each listed row.
#'
#' @param sheet_id     sheetId the chart reads its DATA from
#' @param title        chart title
#' @param domain_range c(...) 1-based — labels (the X-axis category column)
#' @param data_range   c(...) 1-based — values
#' @param positive_color list color
#' @param negative_color list color
#' @param subtotal_color list color
#' @param connector_type "DOTTED" | "DASHED" | "SOLID" — connector lines
#' @param subtotal_indices integer vector — which 0-based positions are subtotals
#' @param anchor       c(row, col)
#' @param size         c(width_px, height_px)
#' @param legend       IGNORED. WaterfallChartSpec has no legend field; kept so
#'                     old calls still run. Passing it warns.
#' @param anchor_sheet_id sheetId of the tab the chart SITS on (default `sheet_id`)
#' @param subtotal_labels NULL | character vector, one label per `subtotal_indices`
#'                     entry (recycled), e.g. c("Opening MRR", "Closing MRR")
#' @param subtotal_label text for the subtotal bars' legend/series style
#'                     (default "Subtotal")
#' @param subtotal_is_data TRUE (default) = the listed rows ARE totals; FALSE =
#'                     insert a computed subtotal bar after them
#' @param data_labels  TRUE = print the value on every bar
#' @param offset_x,offset_y,style  as in `fmt_chart_basic()` (`axis_font_size` has
#'                     no effect: a waterfall has no axes)
#' Waterfall charts cannot carry axis titles (the API has none for them).
fmt_chart_waterfall <- function(sheet_id, title,
                                domain_range, data_range,
                                positive_color = list(red = 0.13, green = 0.55, blue = 0.13),
                                negative_color = list(red = 0.78, green = 0.16, blue = 0.16),
                                subtotal_color = list(red = 0.30, green = 0.30, blue = 0.30),
                                connector_type = "DOTTED",
                                subtotal_indices = integer(0L),
                                anchor = c(1L, 1L),
                                size = c(600L, 371L),
                                legend = NULL,
                                anchor_sheet_id = sheet_id,
                                subtotal_labels = NULL,
                                subtotal_label = "Subtotal",
                                subtotal_is_data = TRUE,
                                data_labels = FALSE,
                                offset_x = 0L, offset_y = 0L,
                                style = NULL) {
  if (!is.null(legend))
    warning("fmt_chart_waterfall(): `legend` is ignored; waterfall charts have no legend setting.",
            call. = FALSE)
  ser <- list(
    data = .source_range(sheet_id, data_range),
    positiveColumnsStyle = list(label = "Increase", color = positive_color),
    negativeColumnsStyle = list(label = "Decrease", color = negative_color),
    subtotalColumnsStyle = list(label = subtotal_label, color = subtotal_color)
  )
  if (length(subtotal_indices) > 0L) {
    labels <- if (is.null(subtotal_labels)) NULL else rep_len(subtotal_labels, length(subtotal_indices))
    ser$customSubtotals <- lapply(seq_along(subtotal_indices), function(k) {
      cs <- list(subtotalIndex = as.integer(subtotal_indices[k]),
                 dataIsSubtotal = isTRUE(subtotal_is_data))
      if (!is.null(labels)) cs$label <- labels[k]
      cs
    })
  }
  if (isTRUE(data_labels)) ser$dataLabel <- list(type = "DATA")

  spec_waterfall <- list(
    domain = list(data = .source_range(sheet_id, domain_range)),
    series = list(ser),
    # NOTE: connectorLineStyle has only width + type — colorStyle is rejected.
    connectorLineStyle = list(type = connector_type),
    stackedType = "STACKED"
  )

  .chart_style(list(addChart = list(chart = list(
    spec = list(title = title,
                waterfallChart = spec_waterfall),
    position = .embedded_object_position(anchor_sheet_id, anchor[1L], anchor[2L],
                                         size[1L], size[2L],
                                         as.integer(offset_x), as.integer(offset_y))
  ))), style)
}

# ── Pie / doughnut chart ----------------------------------------------------

#' Build an `addChart` request for a pie chart, or a doughnut with `donut = TRUE`.
#'
#' Slice colors come from the spreadsheet theme accents (ACCENT1..6); change them
#' with an `updateSpreadsheetProperties` theme request, not per slice.
#'
#' @param sheet_id     sheetId the chart reads its DATA from
#' @param title        chart title
#' @param domain_range c(...) 1-based — slice labels (one column or one row)
#' @param data_range   c(...) 1-based — slice values, same length as the labels.
#'                     A header cell is NOT used; start both ranges on data rows.
#' @param donut        TRUE = doughnut (hole of size `pie_hole`)
#' @param pie_hole     hole radius as a fraction, 0-1 (default 0.55); used when `donut`
#' @param legend       "RIGHT_LEGEND" (default) | "BOTTOM_LEGEND" | "LEFT_LEGEND" |
#'                     "TOP_LEGEND" | "NO_LEGEND" | "LABELED_LEGEND"
#' @param anchor,size,anchor_sheet_id  as in `fmt_chart_basic()`
#' @param offset_x,offset_y,style  as in `fmt_chart_basic()` (`axis_font_size` has
#'                     no effect: a pie has no axes)
fmt_chart_pie <- function(sheet_id, title, domain_range, data_range,
                          donut = FALSE, pie_hole = 0.55,
                          legend = "RIGHT_LEGEND",
                          anchor = c(1L, 1L),
                          size = c(450L, 300L),
                          anchor_sheet_id = sheet_id,
                          offset_x = 0L, offset_y = 0L,
                          style = NULL) {
  pie <- list(legendPosition = legend,
              domain = .source_range(sheet_id, domain_range),
              series = .source_range(sheet_id, data_range))
  if (isTRUE(donut)) pie$pieHole <- pie_hole
  .chart_style(list(addChart = list(chart = list(
    spec = list(title = title, pieChart = pie),
    position = .embedded_object_position(anchor_sheet_id, anchor[1L], anchor[2L],
                                         size[1L], size[2L],
                                         as.integer(offset_x), as.integer(offset_y))
  ))), style)
}
