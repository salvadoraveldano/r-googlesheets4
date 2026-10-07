# =============================================================================
# gs_modern.R — Modern Sheets API features
# =============================================================================
#
# Coverage that the original skill missed:
#   * Banded ranges        (addBanding)             — alternating-row tables
#   * Pivot tables         (updateCells.pivotTable) — summary tabs
#   * Filter views         (addFilterView)          — saved per-user views
#   * Protected ranges     (addProtectedRange)      — lock cells from edits
#   * Slicers              (addSlicer)              — chart filter chips
#   * Image cells          (updateCells / =IMAGE()) — embedded images
#   * findReplace          (findReplace)            — bulk text edits
#   * autoResizeDimensions (autoResizeDimensions)   — column auto-fit
#
# Sourcing order: gs_helpers.R first.
# =============================================================================

if (!exists("grid_range")) stop("Source gs_helpers.R before gs_modern.R")

# ── Banded ranges -----------------------------------------------------------

#' Apply alternating-row banding to a range. Much cleaner than per-row
#' `repeatCell` for table styling.
#'
#' Note: banded background colors get OVERRIDDEN by any later `repeatCell`
#' that sets `backgroundColor` on the same cells (last-writer-wins). Apply
#' banding LAST in your batch, or skip per-row bg colors elsewhere.
fmt_banding <- function(sheet_id, start_row, end_row, start_col, end_col,
                        header_color = NULL, footer_color = NULL,
                        first_band   = hex_to_color("FFFFFF"),
                        second_band  = hex_to_color("F3F3F3")) {
  band_props <- list(firstBandColorStyle  = list(rgbColor = first_band),
                     secondBandColorStyle = list(rgbColor = second_band))
  if (!is.null(header_color))
    band_props$headerColorStyle <- list(rgbColor = header_color)
  if (!is.null(footer_color))
    band_props$footerColorStyle <- list(rgbColor = footer_color)

  list(addBanding = list(
    bandedRange = list(
      range = grid_range(sheet_id, start_row, end_row, start_col, end_col),
      rowProperties = band_props
    )
  ))
}

# ── Pivot tables ------------------------------------------------------------

#' Build a pivot table at `anchor` cell, sourced from `source_range`.
#'
#' @param sheet_id     destination sheetId
#' @param anchor_row   1-based row where pivot top-left lands
#' @param anchor_col   1-based col
#' @param source_sheet_id sheetId of the data source
#' @param source_range c(start_row, end_row, start_col, end_col) of source
#' @param rows         list of list(sourceColumnOffset = 0L, showTotals = TRUE,
#'                      sortOrder = "ASCENDING")
#' @param columns      same shape as rows (omit/NULL for none)
#' @param values       list of list(sourceColumnOffset = N, summarizeFunction =
#'                      "SUM"|"AVERAGE"|"COUNTA"|"MAX"|"MIN", name = "Total")
#' @param filters      named list of column-offset → list(visibleValues = ...)
fmt_pivot_table <- function(sheet_id, anchor_row, anchor_col,
                            source_sheet_id, source_range,
                            rows = list(), columns = list(),
                            values = list(), filters = list()) {
  pivot <- list(
    source = grid_range(source_sheet_id, source_range[1L], source_range[2L],
                        source_range[3L], source_range[4L]),
    rows    = rows,
    columns = columns,
    values  = values,
    valueLayout = "HORIZONTAL"
  )
  if (length(filters) > 0L) pivot$criteria <- filters

  list(updateCells = list(
    rows = list(list(values = list(list(pivotTable = pivot)))),
    start = list(sheetId = sheet_id,
                 rowIndex = anchor_row - 1L,
                 columnIndex = anchor_col - 1L),
    fields = "pivotTable"
  ))
}

# ── Filter views ------------------------------------------------------------

#' Create a saved filter view. Filter views are per-user — they don't change
#' the underlying data, just the way one user sees it.
#'
#' @param sheet_id      sheetId
#' @param start_row,end_row,start_col,end_col  range bounds (1-based)
#' @param title         filter view title
#' @param sort_specs    optional list of list(dimensionIndex = 0L,
#'                       sortOrder = "ASCENDING"|"DESCENDING")
#' @param criteria      named list keyed by 0-based col index → list(
#'                       hiddenValues = c(...) or condition = list(...))
fmt_filter_view <- function(sheet_id, start_row, end_row, start_col, end_col,
                            title, sort_specs = list(), criteria = list()) {
  fv <- list(
    title = title,
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col)
  )
  if (length(sort_specs) > 0L) fv$sortSpecs <- sort_specs
  if (length(criteria)   > 0L) fv$criteria  <- criteria
  list(addFilterView = list(filter = fv))
}

# ── Protected ranges --------------------------------------------------------

#' Protect a range from edits. With `warning_only = TRUE`, edits show a
#' warning prompt but are not blocked. Use `warning_only = FALSE` plus a
#' non-empty `editor_emails` to enforce.
#'
#' @param sheet_id      sheetId
#' @param start_row,end_row,start_col,end_col  range bounds (1-based)
#' @param description   user-visible description
#' @param warning_only  if TRUE, advisory; if FALSE, enforced (requires editors)
#' @param editor_emails character vector of allowed editor emails (when not
#'                      warning_only)
fmt_protected_range <- function(sheet_id, start_row, end_row, start_col, end_col,
                                description = "Protected", warning_only = TRUE,
                                editor_emails = character(0L)) {
  pr <- list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    description = description,
    warningOnly = warning_only
  )
  if (!warning_only && length(editor_emails) > 0L) {
    pr$editors <- list(users = as.list(editor_emails))
  }
  list(addProtectedRange = list(protectedRange = pr))
}

# ── Slicers -----------------------------------------------------------------

#' Add a slicer (filter chip) anchored at a cell, sourced from a data range.
#' Slicers filter charts and pivot tables that share the source.
#'
#' @param sheet_id          destination sheetId
#' @param source_sheet_id   sheetId of the data the slicer filters
#' @param source_range      c(start_row, end_row, start_col, end_col)
#' @param column_index      0-based col within source the slicer filters
#' @param anchor_row,anchor_col  1-based anchor for slicer top-left
#' @param title             user-visible label
#' @param size              c(width_px, height_px)
fmt_slicer <- function(sheet_id, source_sheet_id, source_range, column_index,
                       anchor_row, anchor_col, title = "Filter",
                       size = c(200L, 30L)) {
  list(addSlicer = list(slicer = list(
    spec = list(
      dataRange = grid_range(source_sheet_id, source_range[1L], source_range[2L],
                             source_range[3L], source_range[4L]),
      filterSpec = list(filterCriteria = list(visibleValues = list()),
                        columnIndex = column_index),
      title = title,
      applyToPivotTables = TRUE
    ),
    position = list(overlayPosition = list(
      anchorCell = list(sheetId = sheet_id,
                        rowIndex = anchor_row - 1L,
                        columnIndex = anchor_col - 1L),
      widthPixels  = size[1L],
      heightPixels = size[2L]
    ))
  )))
}

# ── Image embedding ---------------------------------------------------------

#' Embed an image into a cell.
#'
#' Two modes:
#'   * "IN_CELL"   — uses the `=IMAGE("url")` formula. Image scales inside the
#'                   cell. Works in regular reads / exports.
#'   * "OVER_CELL" — uses an embedded object positioned over the cell. The
#'                   image floats above the grid; resize freely. Requires the
#'                   image to be reachable from Google's servers.
#'
#' @param sheet_id  sheetId
#' @param row,col   1-based anchor
#' @param image_url public URL of the image
#' @param mode      "IN_CELL" | "OVER_CELL"
#' @param size      c(width_px, height_px) — only used for OVER_CELL
fmt_image_cell <- function(sheet_id, row, col, image_url,
                           mode = c("IN_CELL", "OVER_CELL"),
                           size = c(200L, 200L)) {
  mode <- match.arg(mode)
  if (mode == "IN_CELL") {
    list(updateCells = list(
      rows = list(list(values = list(list(
        userEnteredValue = list(formulaValue = sprintf('=IMAGE("%s")', image_url))
      )))),
      start = list(sheetId = sheet_id,
                   rowIndex = row - 1L, columnIndex = col - 1L),
      fields = "userEnteredValue"
    ))
  } else {
    # OVER_CELL: an embeddedObject "image" positioned at the anchor.
    list(updateEmbeddedObjectPosition = list(
      objectId = NULL,
      newPosition = list(overlayPosition = list(
        anchorCell = list(sheetId = sheet_id,
                          rowIndex = row - 1L, columnIndex = col - 1L),
        widthPixels  = size[1L],
        heightPixels = size[2L]
      )),
      fields = "*"
    ))
    # NOTE: actual image upload uses the Drive API (drive_upload + image
    # MIME type) plus an `addChart` workaround for true overlay images.
    # For most cases, IN_CELL via =IMAGE() URL is the simpler path.
  }
}

# ── Bulk text find/replace --------------------------------------------------

#' Find and replace across a sheet, the whole spreadsheet, or a range.
#'
#' @param find_text     literal string or regex
#' @param replacement   replacement string
#' @param sheet_id      NULL = whole spreadsheet; otherwise restrict to sheet
#' @param all_sheets    TRUE to search all sheets
#' @param match_case    case-sensitive search
#' @param match_entire_cell  match only whole-cell content
#' @param search_by_regex    treat find_text as regex
fmt_find_replace <- function(find_text, replacement,
                             sheet_id = NULL, all_sheets = FALSE,
                             match_case = FALSE, match_entire_cell = FALSE,
                             search_by_regex = FALSE) {
  fr <- list(
    find = find_text,
    replacement = replacement,
    matchCase = match_case,
    matchEntireCell = match_entire_cell,
    searchByRegex = search_by_regex
  )
  if (all_sheets) {
    fr$allSheets <- TRUE
  } else if (!is.null(sheet_id)) {
    fr$sheetId <- sheet_id
  }
  list(findReplace = fr)
}

# ── Auto-resize columns -----------------------------------------------------

#' Auto-fit a column range to its content. Called on the API side (vs
#' `range_autofit()` from googlesheets4) so it can be batched with other
#' formatting requests.
fmt_auto_resize_cols <- function(sheet_id, start_col, end_col) {
  list(autoResizeDimensions = list(dimensions = list(
    sheetId = sheet_id, dimension = "COLUMNS",
    startIndex = start_col - 1L, endIndex = end_col
  )))
}
