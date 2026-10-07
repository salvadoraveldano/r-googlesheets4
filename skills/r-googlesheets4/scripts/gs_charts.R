# =============================================================================
# gs_charts.R — Native Google Sheets charts via addChart batchUpdate
# =============================================================================
#
# Two spec families cover most needs:
#   * basicChart    — LINE, COLUMN, BAR, SCATTER, AREA, COMBO (with STACKED)
#   * waterfallChart
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
#
# Sourcing order: gs_helpers.R first.
# =============================================================================

if (!exists("grid_range")) stop("Source gs_helpers.R before gs_charts.R")

# ── Internal: build a sourceRange from c(start_row, end_row, start_col, end_col)
.source_range <- function(sheet_id, range4) {
  list(sources = list(grid_range(sheet_id, range4[1L], range4[2L],
                                 range4[3L], range4[4L])))
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

# ── Basic chart -------------------------------------------------------------

#' Build an `addChart` request for a basic chart (LINE / COLUMN / BAR / AREA /
#' SCATTER / COMBO).
#'
#' @param sheet_id      sheetId to render the chart on
#' @param title         chart title
#' @param chart_type    "LINE" | "COLUMN" | "BAR" | "AREA" | "SCATTER" | "COMBO"
#' @param domain_range  c(start_row, end_row, start_col, end_col) — 1-based, inclusive
#' @param series_list   list of per-series specs:
#'                      list(range = c(...), color = list(red,green,blue),
#'                           axis = "LEFT_AXIS"|"RIGHT_AXIS"|"BOTTOM_AXIS",
#'                           type = "LINE"|"COLUMN" (for COMBO))
#' @param header_count  1L when first cell of each range is the legend label
#' @param stacked_type  NULL | "STACKED" | "PERCENT_STACKED"
#' @param anchor        c(row, col) — 1-based anchor for the chart's top-left
#' @param size          c(width_px, height_px)
#' @param legend        "BOTTOM_LEGEND" | "LEFT_LEGEND" | "RIGHT_LEGEND" |
#'                      "TOP_LEGEND" | "NO_LEGEND"
fmt_chart_basic <- function(sheet_id, title, chart_type,
                            domain_range, series_list,
                            header_count = 1L,
                            stacked_type = NULL,
                            anchor = c(1L, 1L),
                            size = c(600L, 371L),
                            legend = "BOTTOM_LEGEND") {
  series <- lapply(series_list, function(s) {
    target_axis <- s$axis %||%
      (if (chart_type == "BAR") "BOTTOM_AXIS" else "LEFT_AXIS")
    out <- list(
      series = .source_range(sheet_id, s$range),
      targetAxis = target_axis
    )
    if (!is.null(s$color)) out$colorStyle <- list(rgbColor = s$color)
    if (!is.null(s$type)) out$type <- s$type
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

  list(addChart = list(chart = list(
    spec = list(title = title, basicChart = basic),
    position = .embedded_object_position(sheet_id, anchor[1L], anchor[2L],
                                         size[1L], size[2L])
  )))
}

# ── BAR (horizontal) — convenience wrapper that defaults BOTTOM_AXIS --------

#' Horizontal BAR chart. Forces BOTTOM_AXIS on every series unless overridden
#' (Sheets rejects BAR series targeting LEFT_AXIS with HTTP 400).
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
#' @param sheet_id     sheetId to render on
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
fmt_chart_waterfall <- function(sheet_id, title,
                                domain_range, data_range,
                                positive_color = list(red = 0.13, green = 0.55, blue = 0.13),
                                negative_color = list(red = 0.78, green = 0.16, blue = 0.16),
                                subtotal_color = list(red = 0.30, green = 0.30, blue = 0.30),
                                connector_type = "DOTTED",
                                subtotal_indices = integer(0L),
                                anchor = c(1L, 1L),
                                size = c(600L, 371L),
                                legend = "BOTTOM_LEGEND") {
  custom_subtotals <- lapply(subtotal_indices, function(i) {
    list(subtotalIndex = as.integer(i), label = "")
  })

  spec_waterfall <- list(
    domain = list(data = .source_range(sheet_id, domain_range)),
    series = list(list(
      data = .source_range(sheet_id, data_range),
      positiveColumnsStyle = list(label = "Increase",
                                  color = positive_color),
      negativeColumnsStyle = list(label = "Decrease",
                                  color = negative_color),
      subtotalColumnsStyle = list(label = "Subtotal",
                                  color = subtotal_color),
      customSubtotals = if (length(custom_subtotals) > 0L) custom_subtotals else NULL
    )),
    # NOTE: connectorLineStyle has only width + type — colorStyle is rejected.
    connectorLineStyle = list(type = connector_type),
    stackedType = "STACKED"
  )

  list(addChart = list(chart = list(
    spec = list(title = title,
                waterfallChart = spec_waterfall),
    position = .embedded_object_position(sheet_id, anchor[1L], anchor[2L],
                                         size[1L], size[2L])
  )))
}
