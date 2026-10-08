# =============================================================================
# gs_helpers.R — Core formatting + I/O helpers for googlesheets4
# =============================================================================
#
# Battle-tested wrappers around the Sheets API v4 `batchUpdate` endpoint plus
# coordinate / color utilities. All `fmt_*` functions return a single request
# object (a list) ready to slot into a `batch_format()` call — except
# `fmt_group_cols()` and `fmt_group_rows()`, which return TWO requests (see
# their headers), `fmt_tab_order()`, which returns one per tab, and
# `fmt_col_widths()`, which returns one per run of equal widths. Use `c()` not
# `list()` when combining those.
#
# Sourcing order: source this file FIRST. `gs_buffer.R`, `gs_qa.R`, and
# `brand.R` depend on `col_letter()`, `hex_to_color()`, and the namespace
# pinning done here.
#
# Requires: googlesheets4 (>= 1.1), googledrive (>= 2.1), gargle, httr, glue.
# =============================================================================

suppressPackageStartupMessages({
  library(googlesheets4)
  library(googledrive)
  library(httr)
  library(glue)
})

# ── Namespace pinning -------------------------------------------------------
# `googlesheets4` and `googledrive` both export request_generate / request_make.
# Last-loaded wins. Pinning here means later `library(googledrive)` calls in
# user code don't break batchUpdate calls with a confusing endpoint error.
request_generate <- googlesheets4::request_generate
request_make     <- googlesheets4::request_make

# Null-coalesce (avoids dragging rlang in for one operator).
`%||%` <- function(a, b) if (is.null(a)) b else a

# ── Coordinates ------------------------------------------------------------

#' 1-based row/col → 0-based GridRange object
#'
#' All Sheets API v4 indices are 0-based and exclusive on the upper bound.
#' This helper takes intuitive 1-based input and produces the API shape.
#'
#' @param sheet_id   numeric Sheet ID (use `get_sheet_id()` to look up by name)
#' @param start_row  1-based first row, inclusive
#' @param end_row    1-based last row, inclusive
#' @param start_col  1-based first col, inclusive
#' @param end_col    1-based last col, inclusive
#' @return list — GridRange ready for batchUpdate
grid_range <- function(sheet_id, start_row, end_row, start_col, end_col) {
  list(
    sheetId          = sheet_id,
    startRowIndex    = start_row - 1L,
    endRowIndex      = end_row,
    startColumnIndex = start_col - 1L,
    endColumnIndex   = end_col
  )
}

#' Column index (1-based) → A1 letter(s). Supports up to ~ZZ (702 cols).
col_letter <- function(col) {
  if (col <= 26L) return(LETTERS[col])
  paste0(LETTERS[(col - 1L) %/% 26L], LETTERS[((col - 1L) %% 26L) + 1L])
}

#' Look up the numeric sheetId for a named tab.
#'
#' Many batchUpdate requests need the sheetId, not the name. The first sheet
#' is usually 0 but never assume — always look up.
get_sheet_id <- function(ss, sheet_name) {
  props <- googlesheets4::sheet_properties(ss)
  ids <- props$id[props$name == sheet_name]
  if (length(ids) == 0L) stop(sprintf("No sheet named '%s'", sheet_name))
  ids[[1L]]
}

# ── Color objects ----------------------------------------------------------

#' Hex string → Sheets API color object (0-1 float RGB).
#'
#' Sheets API does not accept hex. Use this everywhere a color is needed.
hex_to_color <- function(hex) {
  hex <- sub("^#", "", hex)
  list(
    red   = strtoi(substr(hex, 1L, 2L), 16L) / 255,
    green = strtoi(substr(hex, 3L, 4L), 16L) / 255,
    blue  = strtoi(substr(hex, 5L, 6L), 16L) / 255
  )
}

# Generic color constants. Brand-specific colors live in scripts/brand.R.
COL_BLACK        <- list(red = 0, green = 0, blue = 0)
COL_WHITE        <- list(red = 1, green = 1, blue = 1)
COL_LIGHT_GRAY   <- hex_to_color("F5F5F5")
COL_GRAY_TEXT    <- hex_to_color("BDBDBD")
COL_MUTED_TEXT   <- hex_to_color("757575")
COL_RED_TEXT     <- hex_to_color("C62828")
COL_GREEN_LIGHT  <- hex_to_color("C8E6C9")
COL_BLUE_LIGHT   <- hex_to_color("E3F2FD")
COL_YELLOW_LIGHT <- hex_to_color("FFF9C4")
COL_RED_LIGHT    <- hex_to_color("FFCDD2")

# ── Number-format constants ------------------------------------------------

NUMFMT_CURRENCY   <- list(type = "NUMBER",  pattern = '$#,##0;($#,##0);"-"')
NUMFMT_CURRENCY_K <- list(type = "NUMBER",  pattern = '$#,##0,"K";($#,##0,"K");"-"')
NUMFMT_CURRENCY_M <- list(type = "NUMBER",  pattern = '$#,##0,,"M";($#,##0,,"M");"-"')
NUMFMT_PCT        <- list(type = "PERCENT", pattern = "0.0%")
NUMFMT_PCT_WHOLE  <- list(type = "PERCENT", pattern = "0%")
NUMFMT_ACCOUNTING <- list(type = "NUMBER",  pattern = '_($* #,##0_);_($* (#,##0);_($* "-"_)')
NUMFMT_INT        <- list(type = "NUMBER",  pattern = "#,##0")
NUMFMT_DATE       <- list(type = "DATE",    pattern = "yyyy-mm-dd")

# ── repeatCell: font, fill, number-format, alignment -----------------------

#' Build a `repeatCell` request for font / fill / numfmt / alignment.
#'
#' Every parameter is optional. Only the fields you set get applied; the
#' resulting `fields` mask reflects exactly what was specified, so this never
#' clobbers other formatting on the same range. That holds inside the text
#' format too: each text property gets its own mask
#' (`userEnteredFormat.textFormat.fontSize`, `.bold`, `.italic`, `.underline`,
#' `.fontFamily`, `.foregroundColorStyle`), so a later call that sets only
#' `font_size` keeps the bold, colour and family set earlier on those cells, and
#' it keeps a rich-text link (`textFormat.link`). To RESET a property, set it
#' explicitly (`bold = FALSE`); to reset the whole text format, send your own
#' `repeatCell` with the mask `userEnteredFormat.textFormat`.
#'
#' Number format: either `numfmt_type` + `numfmt_pattern`, or `numfmt` = a
#' `list(type = , pattern = )` such as the `NUMFMT_*` constants or your own
#' `list(type = "NUMBER", pattern = '0.0"x"')`. Giving both is an error.
fmt_cells <- function(sheet_id, start_row, end_row, start_col, end_col,
                      font_family = NULL, font_size = NULL, bold = NULL,
                      italic = NULL, underline = NULL,
                      font_color = NULL, bg_color = NULL,
                      numfmt_type = NULL, numfmt_pattern = NULL,
                      halign = NULL, valign = NULL, wrap = NULL,
                      numfmt = NULL) {

  if (!is.null(numfmt)) {
    if (!is.null(numfmt_type) || !is.null(numfmt_pattern))
      stop("fmt_cells: pass `numfmt` OR numfmt_type/numfmt_pattern, not both", call. = FALSE)
    if (!is.list(numfmt) || is.null(numfmt$type))
      stop("fmt_cells: `numfmt` must be list(type = , pattern = ), e.g. NUMFMT_CURRENCY", call. = FALSE)
    numfmt_type <- numfmt$type
    numfmt_pattern <- numfmt$pattern
  }

  format <- list()
  fields <- character()

  # font
  text_format <- list()
  if (!is.null(font_family)) text_format$fontFamily <- font_family
  if (!is.null(font_size))   text_format$fontSize   <- font_size
  if (!is.null(bold))        text_format$bold       <- bold
  if (!is.null(italic))      text_format$italic     <- italic
  if (!is.null(underline))   text_format$underline  <- underline
  if (!is.null(font_color))  text_format$foregroundColorStyle <- list(rgbColor = font_color)
  if (length(text_format) > 0L) {
    format$textFormat <- text_format
    fields <- c(fields, paste0("userEnteredFormat.textFormat.", names(text_format)))
  }

  # fill
  if (!is.null(bg_color)) {
    format$backgroundColor <- bg_color
    fields <- c(fields, "userEnteredFormat.backgroundColor")
  }

  # number format
  if (!is.null(numfmt_type)) {
    format$numberFormat <- list(type = numfmt_type, pattern = numfmt_pattern %||% "")
    fields <- c(fields, "userEnteredFormat.numberFormat")
  }

  # alignment / wrap
  if (!is.null(halign)) {
    format$horizontalAlignment <- halign
    fields <- c(fields, "userEnteredFormat.horizontalAlignment")
  }
  if (!is.null(valign)) {
    format$verticalAlignment <- valign
    fields <- c(fields, "userEnteredFormat.verticalAlignment")
  }
  if (!is.null(wrap)) {
    format$wrapStrategy <- if (isTRUE(wrap)) "WRAP" else "OVERFLOW_CELL"
    fields <- c(fields, "userEnteredFormat.wrapStrategy")
  }

  list(repeatCell = list(
    range  = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    cell   = list(userEnteredFormat = format),
    fields = paste(fields, collapse = ",")
  ))
}

# ── Merges ------------------------------------------------------------------

#' Merge a rectangular range. `merge_type` is one of MERGE_ALL / MERGE_COLUMNS /
#' MERGE_ROWS.
#'
#' ⚠ A merge that spans a FROZEN-column boundary is rejected ("You can't merge
#' frozen and non-frozen columns"). Full-width banner merges that include col A
#' therefore require `frozenColumnCount = 0` (freeze rows only). Conversely, a
#' later `fmt_freeze(cols = N)` is rejected if a merge already straddles col N
#' ("you can't freeze columns which contain only part of a merged cell"). See
#' references/pitfalls.md.
fmt_merge <- function(sheet_id, start_row, end_row, start_col, end_col,
                      merge_type = "MERGE_ALL") {
  list(mergeCells = list(
    range     = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    mergeType = merge_type
  ))
}

#' Unmerge any merges within a rectangular range (no-op if none). Pair it with
#' `fmt_merge()` in the SAME batch — unmerge first, then merge — to re-apply a
#' merge registry idempotently when a build deletes+recreates tabs (which wipes
#' merges). Re-merging an identical range otherwise trips "already merged".
#' NB: the range must not PARTIALLY span a merge; pass the exact merge bounds.
fmt_unmerge <- function(sheet_id, start_row, end_row, start_col, end_col) {
  list(unmergeCells = list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col)
  ))
}

# ── Borders -----------------------------------------------------------------

#' Apply borders. Each side parameter is `list(style = "...", color = list)` or
#' NULL (skip). Style ∈ SOLID / SOLID_MEDIUM / SOLID_THICK / DOUBLE / DASHED /
#' DOTTED / NONE.
fmt_borders <- function(sheet_id, start_row, end_row, start_col, end_col,
                        top = NULL, bottom = NULL, left = NULL, right = NULL,
                        inner_h = NULL, inner_v = NULL) {
  bd <- function(spec) {
    if (is.null(spec) || is.null(spec$style)) return(NULL)
    list(style = spec$style,
         colorStyle = list(rgbColor = spec$color %||% COL_BLACK))
  }
  borders <- list(range = grid_range(sheet_id, start_row, end_row, start_col, end_col))
  if (!is.null(top))     borders$top             <- bd(top)
  if (!is.null(bottom))  borders$bottom          <- bd(bottom)
  if (!is.null(left))    borders$left            <- bd(left)
  if (!is.null(right))   borders$right           <- bd(right)
  if (!is.null(inner_h)) borders$innerHorizontal <- bd(inner_h)
  if (!is.null(inner_v)) borders$innerVertical   <- bd(inner_v)
  list(updateBorders = borders)
}

# ── Sheet-level properties --------------------------------------------------

fmt_gridlines <- function(sheet_id, show = FALSE) {
  list(updateSheetProperties = list(
    properties = list(
      sheetId = sheet_id,
      gridProperties = list(hideGridlines = !show)
    ),
    fields = "gridProperties.hideGridlines"
  ))
}

fmt_freeze <- function(sheet_id, rows = 0L, cols = 0L) {
  list(updateSheetProperties = list(
    properties = list(
      sheetId = sheet_id,
      gridProperties = list(
        frozenRowCount    = rows,
        frozenColumnCount = cols
      )
    ),
    fields = "gridProperties.frozenRowCount,gridProperties.frozenColumnCount"
  ))
}

fmt_tab_color <- function(sheet_id, color) {
  list(updateSheetProperties = list(
    properties = list(
      sheetId = sheet_id,
      tabColorStyle = list(rgbColor = color)
    ),
    fields = "tabColorStyle"
  ))
}

#' Requests that put tabs in a given order: one `updateSheetProperties` (index) per
#' tab, so combine with `c()`, not `list()`. The listed tabs take positions 1, 2, 3...
#' in the order given; any tab you leave out follows them in its old order.
#'
#' @param ss    spreadsheet ref (id, URL, sheets_id); looks the tabs up with ONE
#'              `sheet_properties()` call. Pass `NULL` when `tabs` are sheetIds.
#' @param tabs  character vector of tab names in the wanted order, or a numeric
#'              vector of sheetIds (e.g. `unname(sid)`), which needs no API call.
#'              Unknown or repeated entries stop before anything is sent.
#' @examples batch_format(ss, fmt_tab_order(ss, c("Cover", "Data", "Forecast")), strict = TRUE)
fmt_tab_order <- function(ss, tabs) {
  if (!length(tabs) || anyNA(tabs) || anyDuplicated(tabs))
    stop("fmt_tab_order: `tabs` must be a non-empty vector without NA or repeats", call. = FALSE)
  if (is.numeric(tabs)) {
    ids <- tabs
  } else {
    p <- googlesheets4::sheet_properties(ss)
    if (length(miss <- setdiff(tabs, p$name)))
      stop("fmt_tab_order: no such tab(s): ", paste(miss, collapse = ", "), call. = FALSE)
    ids <- p$id[match(tabs, p$name)]
  }
  lapply(seq_along(ids), function(i) list(updateSheetProperties = list(
    properties = list(sheetId = ids[[i]], index = i - 1L), fields = "index")))
}

# ── Spreadsheet theme -------------------------------------------------------

#' Request that sets the spreadsheet THEME colours: the accent palette is what pie
#' and doughnut slices (ACCENT1, ACCENT2, ... in order) pick up, and `link` colours
#' link text. Pie slices cannot be coloured one by one, so
#' this is the way to choose them.
#'
#' ⚠ The API only accepts a COMPLETE theme (all nine colours and a font), so every
#' colour you do not pass resets to Google's default theme and `font_family`
#' resets the theme font (default "Arial"). It does not touch cells that carry
#' their own colours. Each colour is a hex string or an `hex_to_color()` list.
#'
#' @examples batch_format(ss, list(fmt_theme_colors(accent1 = "2457C5", accent2 = "1F9D8B")), strict = TRUE)
fmt_theme_colors <- function(accent1 = "4285F4", accent2 = "EA4335", accent3 = "FBBC04",
                             accent4 = "34A853", accent5 = "FF6D01", accent6 = "46BDC6",
                             text = "000000", background = "FFFFFF", link = "1155CC",
                             font_family = "Arial") {
  cols <- list(TEXT = text, BACKGROUND = background, ACCENT1 = accent1, ACCENT2 = accent2,
               ACCENT3 = accent3, ACCENT4 = accent4, ACCENT5 = accent5, ACCENT6 = accent6,
               LINK = link)
  as_color <- function(x, nm) {
    if (!is.character(x)) return(x)
    if (length(x) != 1L || !grepl("^#?[0-9A-Fa-f]{6}$", x))
      stop("fmt_theme_colors: ", nm, " must be a 6-digit hex colour such as \"2457C5\"", call. = FALSE)
    hex_to_color(x)
  }
  list(updateSpreadsheetProperties = list(
    properties = list(spreadsheetTheme = list(
      primaryFontFamily = font_family,
      themeColors = unname(lapply(names(cols), function(k)
        list(colorType = k, color = list(rgbColor = as_color(cols[[k]], tolower(k))))))
    )),
    fields = "spreadsheetTheme"
  ))
}

# ── Dimensions: width / height ---------------------------------------------

fmt_col_width <- function(sheet_id, start_col, end_col, width_px) {
  list(updateDimensionProperties = list(
    range = list(sheetId = sheet_id, dimension = "COLUMNS",
                 startIndex = start_col - 1L, endIndex = end_col),
    properties = list(pixelSize = width_px),
    fields = "pixelSize"
  ))
}

#' Widths for a run of columns in one call: column `start_col + i - 1` gets
#' `widths[i]`. Runs of equal consecutive widths merge into one request, so
#' `c(220, 90, 90, 90, 140)` gives three requests, not five. Returns a LIST of
#' requests, so combine it with `c()`, not `list()`.
#'
#' @param sheet_id   numeric Sheet ID
#' @param widths     numeric vector of pixel widths, all positive. The API takes
#'                   whole pixels (a fraction is an HTTP 400), so each width is
#'                   rounded first. NA, zero, negative or non-numeric entries
#'                   stop before any request is built
#' @param start_col  1-based column that gets `widths[1]` (default 1 = column A)
#' @return list of `fmt_col_width()` requests
#' @examples batch_format(ss, fmt_col_widths(sid, c(220, 90, 90, 90, 140)), strict = TRUE)
fmt_col_widths <- function(sheet_id, widths, start_col = 1L) {
  if (!is.numeric(widths) || !length(widths) || !all(is.finite(widths) & round(widths) >= 1))
    stop("fmt_col_widths: `widths` must be a non-empty numeric vector of positive pixel widths (no NA)",
         call. = FALSE)
  runs <- rle(as.integer(round(widths)))
  last <- cumsum(runs$lengths)
  lapply(seq_along(last), function(i)
    fmt_col_width(sheet_id, start_col + last[[i]] - runs$lengths[[i]], start_col + last[[i]] - 1L, runs$values[[i]]))
}

fmt_row_height <- function(sheet_id, start_row, end_row, height_px) {
  list(updateDimensionProperties = list(
    range = list(sheetId = sheet_id, dimension = "ROWS",
                 startIndex = start_row - 1L, endIndex = end_row),
    properties = list(pixelSize = height_px),
    fields = "pixelSize"
  ))
}

# ── Group / hide columns and rows ------------------------------------------
# WARNING: these helpers return TWO requests (group + hide). Use `c()` not
# `list()` when combining with other `fmt_*` requests, otherwise batchUpdate
# fails silently.

fmt_group_cols <- function(sheet_id, start_col, end_col, collapsed = TRUE) {
  list(
    list(addDimensionGroup = list(
      range = list(sheetId = sheet_id, dimension = "COLUMNS",
                   startIndex = start_col - 1L, endIndex = end_col)
    )),
    list(updateDimensionProperties = list(
      range = list(sheetId = sheet_id, dimension = "COLUMNS",
                   startIndex = start_col - 1L, endIndex = end_col),
      properties = list(hiddenByUser = collapsed),
      fields = "hiddenByUser"
    ))
  )
}

fmt_group_rows <- function(sheet_id, start_row, end_row, collapsed = TRUE) {
  list(
    list(addDimensionGroup = list(
      range = list(sheetId = sheet_id, dimension = "ROWS",
                   startIndex = start_row - 1L, endIndex = end_row)
    )),
    list(updateDimensionProperties = list(
      range = list(sheetId = sheet_id, dimension = "ROWS",
                   startIndex = start_row - 1L, endIndex = end_row),
      properties = list(hiddenByUser = collapsed),
      fields = "hiddenByUser"
    ))
  )
}

# ── Data validation (dropdowns) --------------------------------------------

#' `input_message` (optional, trailing) is the hint shown when the cell is
#' selected (the rule's `inputMessage`).
fmt_dropdown <- function(sheet_id, start_row, end_row, start_col, end_col, values,
                         input_message = NULL) {
  rule <- list(
    condition = list(
      type = "ONE_OF_LIST",
      values = lapply(values, function(v) list(userEnteredValue = as.character(v)))
    ),
    showCustomUi = TRUE,
    strict = TRUE
  )
  if (!is.null(input_message)) rule$inputMessage <- input_message
  list(setDataValidation = list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    rule = rule
  ))
}

#' `source_range` is an A1-style ref like "=Lists!B2:B13". `input_message` as in
#' `fmt_dropdown()`.
fmt_dropdown_range <- function(sheet_id, start_row, end_row, start_col, end_col,
                               source_range, input_message = NULL) {
  rule <- list(
    condition = list(
      type = "ONE_OF_RANGE",
      values = list(list(userEnteredValue = source_range))
    ),
    showCustomUi = TRUE,
    strict = TRUE
  )
  if (!is.null(input_message)) rule$inputMessage <- input_message
  list(setDataValidation = list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    rule = rule
  ))
}

#' Number / date / text / custom-formula validation (`setDataValidation`) for the
#' condition types the dropdown helpers do not cover, e.g. the yellow input cells
#' of a model: text typed into one is refused instead of cascading `#VALUE!`.
#'
#' `type` and the `values` it takes (a number, a string, a `Date`, or a vector of
#' them):
#'   NUMBER_BETWEEN, NUMBER_NOT_BETWEEN, DATE_BETWEEN, DATE_NOT_BETWEEN   2 values
#'   NUMBER_GREATER, NUMBER_GREATER_THAN_EQ, NUMBER_LESS, NUMBER_LESS_THAN_EQ,
#'   NUMBER_EQ, NUMBER_NOT_EQ, DATE_BEFORE, DATE_AFTER, DATE_ON_OR_BEFORE,
#'   DATE_ON_OR_AFTER, DATE_EQ, TEXT_CONTAINS, TEXT_NOT_CONTAINS, TEXT_EQ  1 value
#'   CUSTOM_FORMULA   1 formula starting with `=`, written for the TOP-LEFT cell
#'                    of the range (`$` locks what must not shift)
#'   DATE_IS_VALID, TEXT_IS_EMAIL, TEXT_IS_URL   no values
#' A date is `"2026-01-31"` / a `Date`, or a formula such as `"=TODAY()"`.
#'
#' ⚠ Validation only guards typing in the UI. Values written through the API
#' (`values.update`, `flush_writes()`, `write_block()`) BYPASS it, so a rule never
#' proves the data is clean: check written values with `read_values()`.
#'
#' @param input_message  hint shown when the cell is selected
#' @param strict         TRUE (default) rejects bad input; FALSE only warns
#' @param show_custom_ui NULL leaves the field out; it matters only for list rules
#' @examples fmt_validation(sid, 5, 50, 3, 3, "NUMBER_BETWEEN", c(0, 1),
#'                          input_message = "A rate from 0 to 1.")
fmt_validation <- function(sheet_id, start_row, end_row, start_col, end_col, type,
                           values = NULL, input_message = NULL, strict = TRUE,
                           show_custom_ui = NULL) {
  arity <- c(NUMBER_BETWEEN = 2L, NUMBER_NOT_BETWEEN = 2L, DATE_BETWEEN = 2L, DATE_NOT_BETWEEN = 2L,
             NUMBER_GREATER = 1L, NUMBER_GREATER_THAN_EQ = 1L, NUMBER_LESS = 1L,
             NUMBER_LESS_THAN_EQ = 1L, NUMBER_EQ = 1L, NUMBER_NOT_EQ = 1L,
             DATE_BEFORE = 1L, DATE_AFTER = 1L, DATE_ON_OR_BEFORE = 1L, DATE_ON_OR_AFTER = 1L,
             DATE_EQ = 1L, TEXT_CONTAINS = 1L, TEXT_NOT_CONTAINS = 1L, TEXT_EQ = 1L,
             CUSTOM_FORMULA = 1L, DATE_IS_VALID = 0L, TEXT_IS_EMAIL = 0L, TEXT_IS_URL = 0L)
  if (!is.character(type) || length(type) != 1L || !type %in% names(arity))
    stop("fmt_validation: `type` must be one of ", paste(names(arity), collapse = ", "),
         " (dropdowns: fmt_dropdown / fmt_dropdown_range)", call. = FALSE)
  values <- unname(as.list(values))   # names would turn the JSON array into an object (HTTP 400)
  if (anyNA(unlist(values)))
    stop("fmt_validation: `values` must not contain NA", call. = FALSE)
  if (length(values) != arity[[type]])
    stop(sprintf("fmt_validation: %s takes %d value(s), got %d", type, arity[[type]], length(values)),
         call. = FALSE)
  vals <- lapply(values, function(v) list(userEnteredValue =
    if (is.numeric(v)) format(v, scientific = FALSE, trim = TRUE, digits = 15) else as.character(v)))
  if (type == "CUSTOM_FORMULA" && !startsWith(vals[[1L]]$userEnteredValue, "="))
    stop("fmt_validation: CUSTOM_FORMULA needs a formula that starts with '=': ",
         vals[[1L]]$userEnteredValue, call. = FALSE)
  cond <- list(type = type)
  if (length(vals)) cond$values <- vals
  rule <- list(condition = cond, strict = isTRUE(strict))
  if (!is.null(show_custom_ui)) rule$showCustomUi <- isTRUE(show_custom_ui)
  if (!is.null(input_message)) rule$inputMessage <- input_message
  list(setDataValidation = list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    rule = rule
  ))
}

# ── Basic filter ------------------------------------------------------------

#' Set the sheet's basic filter (the funnel icon) over a range; the header row
#' is the first row of the range. `setBasicFilter` REPLACES any filter already on
#' the tab, so re-running is idempotent (a tab holds one basic filter).
fmt_basic_filter <- function(sheet_id, start_row, end_row, start_col, end_col) {
  list(setBasicFilter = list(filter = list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col)
  )))
}

# ── Named ranges ------------------------------------------------------------

fmt_named_range <- function(sheet_id, name, start_row, end_row, start_col, end_col) {
  # Sheets-enforced naming rule: ^[A-Za-z_][A-Za-z0-9_]*$
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", name)) {
    stop(sprintf("Invalid named range '%s' — must match ^[A-Za-z_][A-Za-z0-9_]*$", name))
  }
  list(addNamedRange = list(
    namedRange = list(
      name  = name,
      range = grid_range(sheet_id, start_row, end_row, start_col, end_col)
    )
  ))
}

# ── Conditional formatting --------------------------------------------------

fmt_cond_negative <- function(sheet_id, start_row, end_row, start_col, end_col,
                              color = COL_RED_TEXT, index = 0L) {
  list(addConditionalFormatRule = list(
    rule = list(
      ranges = list(grid_range(sheet_id, start_row, end_row, start_col, end_col)),
      booleanRule = list(
        condition = list(
          type = "NUMBER_LESS",
          values = list(list(userEnteredValue = "0"))
        ),
        format = list(
          textFormat = list(foregroundColorStyle = list(rgbColor = color))
        )
      )
    ),
    index = index
  ))
}

fmt_cond_color_scale <- function(sheet_id, start_row, end_row, start_col, end_col,
                                 min_color = COL_GREEN_LIGHT,
                                 mid_color = COL_YELLOW_LIGHT,
                                 max_color = COL_RED_LIGHT, index = 0L) {
  list(addConditionalFormatRule = list(
    rule = list(
      ranges = list(grid_range(sheet_id, start_row, end_row, start_col, end_col)),
      gradientRule = list(
        minpoint = list(color = min_color, type = "MIN"),
        midpoint = list(color = mid_color, type = "PERCENTILE", value = "50"),
        maxpoint = list(color = max_color, type = "MAX")
      )
    ),
    index = index
  ))
}

# Boolean rules. `index` is the rule's PRIORITY on the tab (0 = highest) and the
# rule is INSERTED there: with the default 0, each rule added later in the same
# batch lands above the earlier ones and wins. For "first listed wins" pass
# index = 0, 1, 2, ... in listing order.
.cond_rule <- function(sheet_id, start_row, end_row, start_col, end_col,
                       type, values, bg_color, font_color, bold, index) {
  if (is.null(bg_color) && is.null(font_color) && is.null(bold))
    stop("Conditional rule needs at least one of bg_color, font_color, bold", call. = FALSE)
  format <- list()
  if (!is.null(bg_color)) format$backgroundColorStyle <- list(rgbColor = bg_color)
  text_format <- list()
  if (!is.null(font_color)) text_format$foregroundColorStyle <- list(rgbColor = font_color)
  if (!is.null(bold))       text_format$bold <- bold
  if (length(text_format)) format$textFormat <- text_format
  list(addConditionalFormatRule = list(
    rule = list(
      ranges = list(grid_range(sheet_id, start_row, end_row, start_col, end_col)),
      booleanRule = list(
        condition = list(type = type,
                         values = lapply(values, function(v) list(userEnteredValue = v))),
        format = format
      )
    ),
    index = index
  ))
}

#' CUSTOM_FORMULA rule: `formula` is evaluated per cell, written for the TOP-LEFT
#' cell of the range with `$` locking what must not shift, e.g.
#' `fmt_cond_formula(sid, 4, 200, 1, 9, '=$H4="Overdue"', bg_color = COL_RED_LIGHT)`.
#' It must start with `=`. ⚠ The formula cannot point at another tab: neither a
#' NAMED RANGE that lives there nor a plain `Tab!A1` ref (HTTP 400 'Invalid
#' ConditionValue.userEnteredValue'). Echo the value into a same-tab cell and
#' point the rule at that cell, or use `INDIRECT("Tab!A1")`.
#' See references/conditional-formatting.md.
fmt_cond_formula <- function(sheet_id, start_row, end_row, start_col, end_col, formula,
                             bg_color = NULL, font_color = NULL, bold = NULL,
                             index = 0L) {
  if (!startsWith(formula, "=")) stop("fmt_cond_formula: formula must start with '=': ", formula, call. = FALSE)
  .cond_rule(sheet_id, start_row, end_row, start_col, end_col,
             "CUSTOM_FORMULA", list(formula), bg_color, font_color, bold, index)
}

#' Text rule: highlight cells whose text `op` `text`. `op` is "equals",
#' "starts_with", "contains" or "not_contains" (TEXT_EQ / TEXT_STARTS_WITH /
#' TEXT_CONTAINS / TEXT_NOT_CONTAINS); the match ignores case, a number matches on
#' its displayed text, and "not_contains" also lights EMPTY cells, so keep its range
#' to the rows that hold data. `text` comes after `op`, so pass it by name:
#' `fmt_cond_text(sid, 4, 200, 8, 8, op = "contains", text = "late", bg_color = COL_RED_LIGHT)`.
fmt_cond_text <- function(sheet_id, start_row, end_row, start_col, end_col,
                          op = c("equals", "starts_with", "contains", "not_contains"), text,
                          bg_color = NULL, font_color = NULL, bold = NULL,
                          index = 0L) {
  op <- match.arg(op)
  if (missing(text) || length(text) != 1L)
    stop("fmt_cond_text: pass one `text` to match, e.g. text = \"Done\"", call. = FALSE)
  type <- c(equals = "TEXT_EQ", starts_with = "TEXT_STARTS_WITH", contains = "TEXT_CONTAINS",
            not_contains = "TEXT_NOT_CONTAINS")[[op]]
  .cond_rule(sheet_id, start_row, end_row, start_col, end_col,
             type, list(as.character(text)), bg_color, font_color, bold, index)
}

#' TEXT_EQ rule: highlight cells whose text equals `text` (`fmt_cond_text(op = "equals")`).
fmt_cond_text_equals <- function(sheet_id, start_row, end_row, start_col, end_col, text,
                                 bg_color = NULL, font_color = NULL, bold = NULL,
                                 index = 0L) {
  fmt_cond_text(sheet_id, start_row, end_row, start_col, end_col, op = "equals", text = text,
                bg_color = bg_color, font_color = font_color, bold = bold, index = index)
}

#' Number comparison rule. `op` is one of "greater", "less", "greater_eq",
#' "less_eq" (NUMBER_GREATER / NUMBER_LESS / NUMBER_GREATER_THAN_EQ /
#' NUMBER_LESS_THAN_EQ). `value` is a number.
fmt_cond_number <- function(sheet_id, start_row, end_row, start_col, end_col, value,
                            op = c("greater", "less", "greater_eq", "less_eq"),
                            bg_color = NULL, font_color = NULL, bold = NULL,
                            index = 0L) {
  op <- match.arg(op)
  type <- c(greater = "NUMBER_GREATER", less = "NUMBER_LESS",
            greater_eq = "NUMBER_GREATER_THAN_EQ", less_eq = "NUMBER_LESS_THAN_EQ")[[op]]
  .cond_rule(sheet_id, start_row, end_row, start_col, end_col, type,
             list(format(value, scientific = FALSE, trim = TRUE, digits = 15)),
             bg_color, font_color, bold, index)
}

# ── Rich-text links ---------------------------------------------------------

#' Write a column of label cells that carry REAL rich-text links.
#'
#' ⚠ Do NOT write link columns as `=HYPERLINK()` formulas via the values API:
#' API-written HYPERLINK formulas evaluate (the label shows) but Sheets never
#' generates the evaluated `hyperlink` metadata, so clicking does nothing until
#' a human re-enters the cell (enter → space → enter). This helper writes the
#' label as a string with `textFormat.link.uri` — always clickable on first
#' click, renders as the standard blue underlined link.
#'
#' One request covers `length(labels)` vertical cells starting at (row1, col1).
#' Empty/NA url or label → the cell is written as an empty string (cleared).
#'
#' ⚠ Colour: only `textFormat.link` is written, so the cells keep whatever text
#' colour they already had (plain black unless coloured before). Pre-colour the
#' link cells blue (and underline them) with `fmt_cells(font_color = , underline =
#' TRUE)` in an EARLIER batch; the link then keeps that look.
#' Ordering: `fmt_cells()` masks each text property on its own, so it no longer
#' wipes a link. A hand-written `repeatCell` whose mask is the whole
#' `userEnteredFormat` or `userEnteredFormat.textFormat` still does, so send
#' those before the link requests.
link_cells_req <- function(sheet_id, row1, col1, labels, urls) {
  rows <- lapply(seq_along(labels), function(i) {
    ok <- !is.na(urls[i]) && nzchar(urls[i]) && !is.na(labels[i]) && nzchar(labels[i])
    if (!ok) return(list(values = list(list(userEnteredValue = list(stringValue = "")))))
    list(values = list(list(
      userEnteredValue = list(stringValue = as.character(labels[i])),
      userEnteredFormat = list(textFormat = list(link = list(uri = as.character(urls[i]))))
    )))
  })
  list(updateCells = list(
    start = list(sheetId = sheet_id, rowIndex = as.integer(row1 - 1L),
                 columnIndex = as.integer(col1 - 1L)),
    rows = rows,
    fields = "userEnteredValue,userEnteredFormat.textFormat.link"
  ))
}

#' Parse an `=HYPERLINK("url","label")` content string -> list(url, label), or
#' NULL if it doesn't match. Use to migrate existing HYPERLINK content strings
#' to `link_cells_req()` (labels with escaped `""` quotes are unescaped).
parse_hyperlink <- function(v) {
  m <- regmatches(v, regexec('^=HYPERLINK\\("([^"]+)","(.*)"\\)$', v))[[1]]
  if (length(m) != 3) return(NULL)
  list(url = m[2], label = gsub('""', '"', m[3]))
}

#' Set the NOTE (the hover comment) on ONE cell: an `updateCells` request whose
#' mask is `note` alone, so the cell's value and format stay as they are. An empty
#' string clears the note. ⚠ Sheets' PDF export prints every note as a `[n]` marker
#' plus an extra page, so keep notes off tabs you export for `visual_qa()`.
#'
#' @param sheet_id  numeric Sheet ID
#' @param row,col   1-based cell, as in `fmt_cells()`
#' @param text      the note, one string; `""` clears the note
#' @return one request
#' @examples batch_format(ss, list(fmt_note(sid, 3, 15, "Risk score, 0 to 100.")), strict = TRUE)
fmt_note <- function(sheet_id, row, col, text) {
  if (!is.character(text) || length(text) != 1L || is.na(text))
    stop("fmt_note: `text` must be one string (\"\" clears the note)", call. = FALSE)
  list(updateCells = list(
    range  = grid_range(sheet_id, row, row, col, col),
    rows   = list(list(values = list(list(note = text)))),
    fields = "note"
  ))
}

#' Auto-fit row heights to wrapped content (the row analog of
#' `fmt_auto_resize_cols()` in gs_modern.R). Overrides previously pinned
#' `fmt_row_height()` values — use for narrative rows whose wrapped text length
#' varies too much to pin, and keep pins only for structural rows (titles,
#' headers, spacers). Place LAST in the batch so it sees final widths/wraps.
fmt_auto_resize_rows <- function(sheet_id, start_row, end_row) {
  list(autoResizeDimensions = list(dimensions = list(
    sheetId = sheet_id, dimension = "ROWS",
    startIndex = as.integer(start_row - 1L), endIndex = as.integer(end_row)
  )))
}

# ── batchUpdate dispatcher --------------------------------------------------

#' Send a list of formatting requests in ONE batchUpdate call.
#'
#' ALWAYS checks HTTP status. `request_make()` does NOT throw on HTTP 400 — it
#' silently returns the failed response. Without this status check, formatting
#' appears to succeed but nothing is applied.
#'
#' batchUpdate is atomic: ONE bad request fails ALL requests in the batch. So
#' when applying INDEPENDENT cosmetic ops across many tabs, prefer one
#' `batch_format()` call PER TAB — a failure on one tab then can't nuke the rest.
#'
#' ⚠ This logs HTTP failures via `message()` but, by default, does NOT throw —
#' so `tryCatch(batch_format(...))` will NOT catch a 400, and the `message()`
#' can scroll off / be hidden by `grep|tail`. To detect failures, either pass
#' `strict = TRUE` (stops on HTTP ≥ 400) or RE-READ the live state afterwards;
#' do not trust a self-reported "success".
#'
#' @param ss        spreadsheet ref (sheets_id, dribble, or character ID)
#' @param requests  list of request objects (each from an `fmt_*` helper); names
#'                  are dropped, the API needs a JSON array
#' @param strict    if TRUE, `stop()` on HTTP ≥ 400 instead of only logging
#' @return invisible httr response
batch_format <- function(ss, requests, strict = FALSE) {
  if (length(requests) == 0L) return(invisible(NULL))
  requests <- unname(requests)   # a NAMED list (e.g. lapply over a named vector) is sent as a JSON object -> 400 'Unknown name "1"'
  ss_id <- as.character(ss)

  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.batchUpdate",
    params = list(spreadsheetId = ss_id, requests = requests)
  )
  resp <- googlesheets4::request_make(req)

  sc <- httr::status_code(resp)
  if (sc >= 400) {
    err <- httr::content(resp, as = "text", encoding = "UTF-8")
    msg <- sprintf("[batch_format] HTTP %d ERROR: %s", sc, substr(err, 1L, 500L))
    if (isTRUE(strict)) stop(msg, call. = FALSE) else message(msg)
  } else {
    n_rep <- length(httr::content(resp, as = "parsed")$replies)
    message(sprintf("[batch_format] %d/%d applied", n_rep, length(requests)))
  }
  invisible(resp)
}

#' Request collector for ONE tab per `batch_format()` call. Returns a list of three
#' functions:
#'   `$push(x)`  add one request (a named one-key list, as every `fmt_*` returns) or
#'               a list of requests (`fmt_col_widths()`, `fmt_group_cols()`, ...);
#'               `unname()` a one-element named list of requests first, or it reads
#'               as a single request
#'   `$cf(f, sheet_id, ...)`  call the conditional-format helper `f` (any `fmt_cond_*`)
#'               as `f(sheet_id, ..., index = k)` and add the result. `k` counts the
#'               rules added through `$cf` FOR THAT `sheet_id`, from 0, so the FIRST
#'               rule listed wins (the helpers' default `index = 0` makes the last
#'               one win). Rule priorities are per tab. Add every conditional-format
#'               rule through `$cf`: a rule pushed with `$push` is not counted, uses
#'               the default `index = 0`, and its final position depends on when it
#'               was pushed (it can reorder the `$cf` rules). Do not pass `index`
#'               yourself.
#'   `$get()`    the requests so far, ready for `batch_format()`
#' @return list(push, cf, get)
#' @examples b <- new_batch()
#'   b$push(fmt_cells(sid, 1, 1, 1, 4, bold = TRUE))
#'   b$cf(fmt_cond_formula, sid, 2, 50, 1, 4, '=$D2="Late"', bg_color = COL_RED_LIGHT)
#'   b$cf(fmt_cond_formula, sid, 2, 50, 1, 4, '=$D2<>""', bg_color = COL_GREEN_LIGHT)
#'   batch_format(ss, b$get(), strict = TRUE)
new_batch <- function() {
  items <- list(); n_cf <- list()
  list(
    push = function(x) {
      if (length(x) == 1L && !is.null(names(x))) x <- list(x)   # a request is a one-key named list
      items <<- c(items, unname(x)); invisible()
    },
    cf = function(f, sheet_id, ...) {
      key <- as.character(sheet_id)
      k <- n_cf[[key]] %||% 0L
      items <<- c(items, list(f(sheet_id, ..., index = k)))
      n_cf[[key]] <<- k + 1L; invisible()
    },
    get = function() items)
}

# ── Reading values ----------------------------------------------------------

#' Read one or several A1 ranges as matrices.
#'
#' One `values.get` call per range: gargle's request builder takes scalar params
#' only, so a vector `ranges` handed to `values.batchGet` fails with 'values must
#' be length 1'. Each range sits in the URL PATH, so it is URL-encoded here (pass
#' it raw; quote tab names that need it: `"'P&L Q1'!A1:C10"`). `request_make()`
#' retries 429 and 500/502/503 with backoff (not 504). A failed call stops with
#' the range in the message.
#'
#' @param ss            spreadsheet ref (id, URL, sheets_id, dribble)
#' @param ranges        character vector of A1 ranges, e.g. `c("Data!A1:D50", "Checks!B2")`
#' @param value_render  `"FORMATTED_VALUE"` (default; what the cell displays, so
#'                      character), `"UNFORMATTED_VALUE"` (raw numbers; dates come
#'                      back as serial numbers), or `"FORMULA"`
#' @return named list (names = `ranges`, or `names(ranges)` when given) of matrices.
#'   A matrix is numeric when every non-blank cell is a number, else character
#'   (numbers written in plain notation). Ragged rows are padded: `NA` in a numeric
#'   matrix, `""` in a character one. A range with no values gives a 0 x 0 matrix.
read_values <- function(ss, ranges, value_render = "FORMATTED_VALUE") {
  ss_id <- as.character(googlesheets4::as_sheets_id(ss))
  out <- lapply(ranges, function(rng) {
    resp <- request_make(request_generate("sheets.spreadsheets.values.get", params = list(
      spreadsheetId = ss_id, range = utils::URLencode(rng, reserved = TRUE),
      valueRenderOption = value_render, dateTimeRenderOption = "SERIAL_NUMBER")))
    if (httr::status_code(resp) >= 400L)
      stop("[read_values] HTTP ", httr::status_code(resp), " for '", rng, "': ",
           substr(httr::content(resp, as = "text", encoding = "UTF-8"), 1L, 300L), call. = FALSE)
    rows <- httr::content(resp, as = "parsed")$values
    if (!length(rows)) return(matrix(character(), 0L, 0L))
    cells <- unlist(rows, recursive = FALSE)
    numeric_only <- any(vapply(cells, is.numeric, NA)) &&
      all(vapply(cells, function(x) is.numeric(x) || identical(x, ""), NA))
    cell <- if (numeric_only) {
      function(x) if (is.numeric(x)) as.numeric(x) else NA_real_
    } else {
      function(x) if (is.null(x)) "" else if (is.numeric(x)) format(x, scientific = FALSE, trim = TRUE, digits = 15) else as.character(x)
    }
    n <- max(lengths(rows))
    do.call(rbind, lapply(rows, function(r) { length(r) <- n; vapply(r, cell, if (numeric_only) 0 else "") }))
  })
  names(out) <- names(ranges) %||% ranges
  out
}

# ── Connect to Google (auth) ------------------------------------------------
# `gs_connect()` replaces the old `gs4_auth(email); drive_auth(token = gs4_token())`
# pair. It reuses the login saved by `scripts/gs_setup.sh auth <email>` and
# NEVER opens a browser: with no saved login it stops with the exact command to
# run. The token's scope follows GS_SCOPE_LEVEL (default: spreadsheets only);
# googledrive is authenticated only at the `export` and `drive` levels.
#
# Resolution order for the account: `email` argument → env GS_EMAIL → the file
# written by gs_setup (~/.config/r-googlesheets4/email). Cached tokens are
# never guessed from. Emails are compared lower-cased (gargle's cache files are
# named after the identity Google reports, which is lower-case).
#
# Env overrides: GS_OAUTH_CACHE (token dir), GS_CONFIG (account file),
# GS_EMAIL (account), GS_SA_JSON (service-account key → headless/cron auth).

# Least privilege: the default level only touches spreadsheets. Raise the level
# (env GS_SCOPE_LEVEL) only when the task needs it, and only after the user agrees:
#   sheets   spreadsheets                         read/write sheets (default)
#   readonly spreadsheets.readonly                read only
#   export   spreadsheets + drive.readonly        also find sheets by name
#   drive    drive                                also share, move, copy, delete files
GS_SCOPE_URL <- "https://www.googleapis.com/auth/"
GS_SCOPE_LEVELS <- list(
  sheets   = paste0(GS_SCOPE_URL, "spreadsheets"),
  readonly = paste0(GS_SCOPE_URL, "spreadsheets.readonly"),
  export   = paste0(GS_SCOPE_URL, c("spreadsheets", "drive.readonly")),
  drive    = paste0(GS_SCOPE_URL, "drive"))
GS_SCOPE_LEVEL <- tolower(Sys.getenv("GS_SCOPE_LEVEL", "sheets"))
if (!GS_SCOPE_LEVEL %in% names(GS_SCOPE_LEVELS))
  stop("GS_SCOPE_LEVEL must be one of: ", paste(names(GS_SCOPE_LEVELS), collapse = ", "), call. = FALSE)
GS_SCOPE       <- GS_SCOPE_LEVELS[[GS_SCOPE_LEVEL]]
GS_EMAIL_SCOPE <- paste0(GS_SCOPE_URL, "userinfo.email")   # gargle adds it
# Absolute path of this scripts/ folder, so printed fix commands work from any
# working directory: where source() found this file, else GS_SKILL_DIR, else ./scripts.
GS_SCRIPTS_DIR <- local({
  for (i in rev(seq_len(sys.nframe()))) {          # find source()'s frame
    f <- tryCatch(get0("ofile", envir = sys.frame(i), inherits = FALSE), error = function(e) NULL)
    if (is.character(f) && length(f) == 1L && file.exists(f)) return(dirname(normalizePath(f)))
  }
  d <- Sys.getenv("GS_SKILL_DIR", "")
  if (nzchar(d) && dir.exists(file.path(d, "scripts"))) return(normalizePath(file.path(d, "scripts")))
  normalizePath("scripts", mustWork = FALSE)
})
GS_SETUP_SH    <- paste("bash", shQuote(file.path(GS_SCRIPTS_DIR, "gs_setup.sh")))
GS_USES_DRIVE  <- GS_SCOPE_LEVEL %in% c("export", "drive")

#' Create the spreadsheet, or reuse it when SHEET_ID is set, so a fix-and-rebuild
#' loop edits one file instead of leaving a new one in Drive each time.
#' `tabs` is a character vector of tab names; missing tabs are added on reuse (with
#' a message naming them, since a tab you did not expect to be missing usually
#' means SHEET_ID points at the wrong file).
#' Prints the id so it can be passed back as SHEET_ID=<id> on the next run.
#'
#' Trailing arguments (all optional):
#'   time_zone  CREATE only. Default `Sys.timezone()`, so datetimes written from R
#'              round-trip (the old behaviour). Pass a zone name for a neutral
#'              file (`"Etc/GMT"`), or NULL to leave Google's default. An NA
#'              `Sys.timezone()` (some containers) is skipped. A reused file keeps
#'              its own time zone.
#'   locale     e.g. `"en_US"` (number/date parsing and TEXT() formats follow it).
#'              On CREATE it sets the locale; NULL = Google's default. On REUSE the
#'              file keeps its locale, so a non-NULL `locale` that differs
#'              from the file's (as Google reports it, e.g. `"de_DE"`) stops BEFORE
#'              adding tabs or changing anything, naming both. NULL skips the check.
#'              Change a file's locale with an `updateSpreadsheetProperties` request.
#'   rows,cols  grid size: one number for every tab, or a vector named by tab
#'              (`cols = c(Forecast = 31)`); an unnamed vector longer than 1
#'              stops; NULL keeps the default (1000 x 26).
#'              Applied on every run, so SHRINKING deletes the cells outside the
#'              new grid.
#'   allow_mismatch  REUSE only. Default FALSE: it stops BEFORE adding tabs or
#'              changing anything when (a) the file's title is not `title` and the
#'              file does not already have ALL of `tabs` (a wrong SHEET_ID would
#'              otherwise get your tabs and, with gs_reset_tabs(), be wiped; a
#'              renamed copy of your own file still passes, because it has all the
#'              tabs, a weak check for generic names like Summary: confirm the id),
#'              or (b) a non-NULL `locale` differs from the file's. TRUE reuses any
#'              file, whatever its title, tabs or locale.
gs_open_or_create <- function(title, tabs, id = Sys.getenv("SHEET_ID", ""),
                              time_zone = Sys.timezone(), locale = NULL,
                              rows = NULL, cols = NULL, allow_mismatch = FALSE) {
  # Checked before anything is created, so a bad call leaves no orphan file in Drive.
  if ((length(rows) > 1L && is.null(names(rows))) || (length(cols) > 1L && is.null(names(cols))))
    stop("gs_open_or_create(): a rows/cols vector longer than 1 must be named by tab, ",
         "e.g. cols = c(Data = 30, Notes = 20).", call. = FALSE)
  if (!nzchar(id)) {
    props <- list()
    if (length(time_zone) == 1L && !is.na(time_zone)) props$timeZone <- time_zone
    if (!is.null(locale)) props$locale <- locale
    ss <- do.call(googlesheets4::gs4_create, c(list(title, sheets = tabs), props))
    message("[gs_open_or_create] created ", as.character(ss), "  (rebuild with SHEET_ID=", as.character(ss), ")")
  } else {
    ss <- googlesheets4::as_sheets_id(id)
    have <- googlesheets4::gs4_get(ss)       # one read: title + tab names, before any write
    if (!isTRUE(allow_mismatch) && !identical(have$name, title) &&
        !(length(tabs) && all(tabs %in% have$sheets$name)))
      stop("[gs_open_or_create] SHEET_ID is a file titled '", have$name, "' but this script builds '", title,
           "' and the file does not have its tabs. Nothing was changed. Confirm the id with the user; ",
           "pass allow_mismatch = TRUE only if they confirm they want to reuse this file.", call. = FALSE)
    if (!isTRUE(allow_mismatch) && !is.null(locale) && !identical(have$locale, locale))
      stop("[gs_open_or_create] SHEET_ID is a file with locale '", have$locale, "' but this script asks for '", locale,
           "', so number, date and TEXT() formats would not read as the script expects. Nothing was changed. ",
           "Confirm the id and the locale with the user; pass allow_mismatch = TRUE only if they confirm they want ",
           "to reuse this file as it is, or change its locale with an updateSpreadsheetProperties request.", call. = FALSE)
    added <- setdiff(tabs, have$sheets$name)
    for (t in added) googlesheets4::sheet_add(ss, sheet = t)
    if (length(added)) message("[gs_open_or_create] added tab(s) not in the file: ",
                               paste(added, collapse = ", "), "  (unexpected? check SHEET_ID)")
    message("[gs_open_or_create] reusing ", id)
  }
  if (!is.null(rows) || !is.null(cols)) {
    size_of <- function(x, tab) {
      v <- if (is.null(x)) NULL else if (is.null(names(x))) x[[1L]] else unname(x[tab])
      if (length(v) == 1L && !is.na(v)) as.integer(v) else NULL
    }
    p <- googlesheets4::sheet_properties(ss)
    reqs <- list()
    for (t in tabs) {
      grid <- list(rowCount = size_of(rows, t), columnCount = size_of(cols, t))
      grid <- grid[!vapply(grid, is.null, NA)]
      if (!length(grid)) next
      reqs[[length(reqs) + 1L]] <- list(updateSheetProperties = list(
        properties = list(sheetId = p$id[p$name == t], gridProperties = grid),
        fields = paste0("gridProperties.", names(grid), collapse = ",")))
    }
    batch_format(ss, reqs, strict = TRUE)
  }
  ss
}

#' Reset tabs to a blank slate so a build script can be re-run in place
#' (`SHEET_ID=<id> Rscript build.R`) without stacking objects or hitting the
#' "already exists" 400s. Tabs and their sheetIds survive.
#'
#' From ONE `spreadsheets.get` it deletes, by id: embedded charts, slicers, tables,
#' banded ranges, protected ranges, filter views, conditional-format rules, row and
#' column groups, and the named ranges that sit on those tabs. Then, per tab, it
#' clears the basic filter, merges, validation, notes, pivot tables, formats and
#' values, un-hides rows/columns and resets row heights (21px) and column widths
#' (100px) over the tab's grid, and un-freezes rows/columns (a leftover freeze
#' makes the next build's banner merge fail). The grid size is left alone.
#'
#' ⚠ Deleting a named range rewrites EVERY formula that uses it to `#REF!`, for
#' good: re-adding the name does not bring the formula back. So reset together
#' every tab whose formulas use the names being deleted (all tabs is always safe),
#' and rewrite those formulas after the reset.
#'
#' @param ss           spreadsheet ref (id, URL, sheets_id, dribble)
#' @param tabs         REQUIRED character vector of tab names; there is no "all
#'                     tabs" default, so a wrong SHEET_ID cannot wipe a whole file
#'                     by accident. To reset every tab, say so on purpose:
#'                     `gs_reset_tabs(ss, googlesheets4::sheet_names(ss))`.
#' @param keep_values  TRUE keeps cell values and formulas and resets everything
#'                     else. Named ranges are then KEPT too (deleting them would
#'                     turn the kept formulas into `#REF!`), so a rebuild must not
#'                     `fmt_named_range()` a name that still exists (HTTP 400).
#' @return invisible httr response of the last batch
#'
#' ⚠ It clears everything on those tabs. Only point it at a file the script owns.
gs_reset_tabs <- function(ss, tabs, keep_values = FALSE) {
  if (missing(tabs) || !is.character(tabs) || !length(tabs) || anyNA(tabs))
    stop("[gs_reset_tabs] `tabs` is required: a character vector of the tab names to wipe. ",
         "To wipe every tab, pass googlesheets4::sheet_names(ss) explicitly. Nothing was changed.", call. = FALSE)
  ss <- googlesheets4::as_sheets_id(ss)   # a URL or dribble resolves, as in read_values()
  resp <- googlesheets4::request_make(googlesheets4::request_generate(
    "sheets.spreadsheets.get", params = list(spreadsheetId = as.character(ss), fields = paste0(
      "namedRanges(namedRangeId,range(sheetId)),",
      "sheets(properties(sheetId,title,gridProperties(rowCount,columnCount)),",
      "charts(chartId),slicers(slicerId),tables(tableId),bandedRanges(bandedRangeId),",
      "protectedRanges(protectedRangeId),filterViews(filterViewId),conditionalFormats(ranges),",
      "rowGroups,columnGroups)"))))
  if (httr::status_code(resp) >= 400L)
    stop("[gs_reset_tabs] spreadsheets.get failed: ", substr(httr::content(resp, as = "text", encoding = "UTF-8"), 1L, 400L), call. = FALSE)
  body <- httr::content(resp, as = "parsed")

  sheets <- body$sheets
  titles <- vapply(sheets, function(s) s$properties$title, "")
  if (length(miss <- setdiff(tabs, titles)))
    stop("[gs_reset_tabs] no such tab(s): ", paste(miss, collapse = ", "), call. = FALSE)
  sheets <- sheets[titles %in% tabs]
  sid_of <- function(x) x %||% 0L        # the API leaves out sheetId 0
  ids <- vapply(sheets, function(s) as.numeric(sid_of(s$properties$sheetId)), 0)
  del <- function(kind, key, id) { r <- list(); r[[kind]] <- stats::setNames(list(id), key); r }

  objs <- list()
  for (n in if (keep_values) NULL else body$namedRanges)
    if (as.numeric(sid_of(n$range$sheetId)) %in% ids)
      objs[[length(objs) + 1L]] <- del("deleteNamedRange", "namedRangeId", n$namedRangeId)
  cells <- list()
  wipe <- paste(c(if (!keep_values) "userEnteredValue", "userEnteredFormat", "dataValidation",
                  "note", "textFormatRuns", "pivotTable"), collapse = ",")
  for (s in sheets) {
    sid <- sid_of(s$properties$sheetId)
    for (x in s$charts)          objs[[length(objs) + 1L]] <- del("deleteEmbeddedObject", "objectId", x$chartId)
    for (x in s$slicers)         objs[[length(objs) + 1L]] <- del("deleteEmbeddedObject", "objectId", x$slicerId)
    for (x in s$tables)          objs[[length(objs) + 1L]] <- del("deleteTable", "tableId", x$tableId)
    # A table carries its own banded range (same id as the table) that disappears with it.
    table_ids <- vapply(s$tables, function(x) as.character(x$tableId), "")
    for (x in s$bandedRanges)
      if (!as.character(x$bandedRangeId) %in% table_ids)
        objs[[length(objs) + 1L]] <- del("deleteBanding", "bandedRangeId", x$bandedRangeId)
    for (x in s$protectedRanges) objs[[length(objs) + 1L]] <- del("deleteProtectedRange", "protectedRangeId", x$protectedRangeId)
    for (x in s$filterViews)     objs[[length(objs) + 1L]] <- del("deleteFilterView", "filterId", x$filterViewId)
    # Descending: each delete shifts the later indices down by one.
    for (i in rev(seq_along(s$conditionalFormats)))
      objs[[length(objs) + 1L]] <- list(deleteConditionalFormatRule = list(sheetId = sid, index = i - 1L))
    # One delete per listed group (each lowers the depth of its range by one),
    # deepest first, so stacked/nested groups from earlier runs all unwind.
    groups <- c(s$rowGroups, s$columnGroups)
    for (g in groups[order(-vapply(groups, function(g) as.numeric(g$depth %||% 1L), 0))]) {
      g$range$sheetId <- sid
      objs[[length(objs) + 1L]] <- list(deleteDimensionGroup = list(range = g$range))
    }
    nr <- s$properties$gridProperties$rowCount; nc <- s$properties$gridProperties$columnCount
    dim_reset <- function(dim, n, px) list(updateDimensionProperties = list(
      range = list(sheetId = sid, dimension = dim, startIndex = 0L, endIndex = n),
      properties = list(pixelSize = px, hiddenByUser = FALSE), fields = "pixelSize,hiddenByUser"))
    cells <- c(cells, list(
      list(clearBasicFilter = list(sheetId = sid)),
      list(unmergeCells = list(range = list(sheetId = sid))),
      list(updateCells = list(range = list(sheetId = sid), fields = wipe)),
      fmt_freeze(sid, 0L, 0L),
      dim_reset("ROWS", nr, 21L), dim_reset("COLUMNS", nc, 100L)))
  }
  # Objects first, in their own batch, so a stale object cannot fail the cell reset.
  batch_format(ss, objs, strict = TRUE)
  batch_format(ss, cells, strict = TRUE)
}

#' Stop with the fix when a task needs more access than the current level.
gs_require_level <- function(what, levels = "drive") {
  if (GS_SCOPE_LEVEL %in% levels) return(invisible(TRUE))
  stop(what, " needs Drive access (GS_SCOPE_LEVEL=", paste(levels, collapse = " or "), "; current: ",
       GS_SCOPE_LEVEL, ").\nAsk the user to approve it, then run once:  GS_SCOPE_LEVEL=", levels[[1]],
       " ", GS_SETUP_SH, " auth <email>   and set GS_SCOPE_LEVEL=", levels[[1]], " for the build script.",
       call. = FALSE)
}

.gs_env <- function(name) { v <- Sys.getenv(name, ""); if (nzchar(v)) v else NULL }

#' Path of the file that remembers the default Google account.
gs_config_path <- function() {
  override <- .gs_env("GS_CONFIG")
  if (!is.null(override)) return(path.expand(override))
  base <- .gs_env("XDG_CONFIG_HOME") %||% file.path(path.expand("~"), ".config")
  file.path(base, "r-googlesheets4", "email")
}

#' Saved default account (lower-cased), or NULL.
gs_config_email <- function() {
  p <- gs_config_path()
  if (!file.exists(p)) return(NULL)
  v <- tolower(trimws(readLines(p, n = 1L, warn = FALSE)))
  if (length(v) && nzchar(v)) v else NULL
}

gs_save_config_email <- function(email) {
  p <- gs_config_path()
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(tolower(trimws(email)), p)
  invisible(p)
}

#' email argument → GS_EMAIL env → config file → NULL. Always lower-cased/trimmed.
gs_resolve_email <- function(email = NULL) {
  if (!is.null(email) && length(email) == 1 && !is.na(email) && nzchar(trimws(email))) {
    return(tolower(trimws(email)))
  }
  env <- .gs_env("GS_EMAIL")
  if (!is.null(env)) return(tolower(trimws(env)))
  gs_config_email()
}

#' Token cache directory: GS_OAUTH_CACHE, else gargle's OS default
#' (macOS ~/Library/Caches/gargle, Linux ~/.cache/gargle).
gs_oauth_cache <- function() {
  override <- .gs_env("GS_OAUTH_CACHE")
  if (!is.null(override)) return(path.expand(override))
  f <- get0("gargle_default_oauth_cache_path", envir = asNamespace("gargle"), inherits = FALSE)
  if (is.function(f)) return(path.expand(f()))
  rappdirs::user_cache_dir("gargle")
}

#' Inventory of saved logins: data.frame(email, scopes, has_scope, file).
#' `has_scope` is TRUE only for a token with exactly the scope set of the current
#' GS_SCOPE_LEVEL (plus userinfo.email) — the only one gargle will match silently.
gs_cached_logins <- function(cache = gs_oauth_cache()) {
  empty <- data.frame(email = character(), scopes = character(),
                      has_scope = logical(), file = character(), stringsAsFactors = FALSE)
  if (!dir.exists(cache)) return(empty)
  files <- list.files(cache, full.names = TRUE)
  files <- files[grepl("_[^/]+@[^/]+$", basename(files)) & !dir.exists(files)]
  if (!length(files)) return(empty)
  bad <- character()
  rows <- lapply(files, function(f) {
    tok <- tryCatch(suppressWarnings(readRDS(f)), error = function(e) NULL)
    if (is.null(tok) || !inherits(tok, "Token2.0")) { bad <<- c(bad, f); return(NULL) }
    em <- tryCatch(tok$email, error = function(e) NULL)
    if (is.null(em) || is.na(em) || !nzchar(em)) em <- sub("^[^_]+_", "", basename(f))
    sc <- tryCatch(as.character(tok$params$scope), error = function(e) character())
    data.frame(email = tolower(em), scopes = paste(sc, collapse = " "),
               has_scope = setequal(sc, c(GS_SCOPE, GS_EMAIL_SCOPE)),
               file = f, stringsAsFactors = FALSE)
  })
  rows <- Filter(Negate(is.null), rows)
  out <- if (length(rows)) do.call(rbind, rows) else empty
  # gargle's cache loader readRDS()es EVERY file in the dir, so one corrupt
  # file breaks every gs4_auth(); `auth` moves such files aside.
  attr(out, "unreadable") <- bad
  out
}

gs_has_login <- function(logins, email) {
  nrow(logins) > 0 && any(logins$email == tolower(email) & logins$has_scope)
}

#' First live API call with a token. At levels with Drive access it also
#' authenticates googledrive and calls drive_user(); otherwise it only touches
#' the Sheets host. `sheets = TRUE` additionally touches the Sheets API host.
#' Returns list(ok = TRUE, user = list(emailAddress = ...)) or
#' list(ok = FALSE, auth_problem = <TRUE if the token is dead>, message = ...).
#' A revoked/expired token fails its refresh here: gargle warns "Unable to
#' refresh token" and deletes the cache file. Network failures are NOT auth
#' problems — the caller must not tell the user to sign in again for those.
gs_live_check <- function(token, sheets = FALSE) {
  refresh_failed <- FALSE
  live <- withCallingHandlers(
    tryCatch({
      if (GS_USES_DRIVE) {
        googledrive::drive_auth(token = token)
        u <- googledrive::drive_user()                   # www.googleapis.com
      } else {
        u <- list(emailAddress = suppressMessages(googlesheets4::gs4_user()))
      }
      if (sheets || !GS_USES_DRIVE) {                                      # sheets.googleapis.com
        # A public example sheet: proves the Sheets host resolves and the token
        # is accepted there (the per-host IPv6 DNS quirk shows up here).
        invisible(googlesheets4::gs4_get(googlesheets4::gs4_example("gapminder")))
      }
      u
    }, error = function(e) e),
    warning = function(w) {
      if (grepl("refresh", conditionMessage(w), ignore.case = TRUE)) {
        refresh_failed <<- TRUE
        invokeRestart("muffleWarning")
      }
    })
  if (!inherits(live, "error")) return(list(ok = TRUE, user = live))
  msg  <- conditionMessage(live)
  code <- tryCatch(httr::status_code(live$resp), error = function(e) NULL)
  auth_problem <- refresh_failed ||
    isTRUE(code %in% c(401L, 403L)) ||
    inherits(live, "http_error_401") || inherits(live, "http_error_403") ||
    grepl("invalid_grant|Unauthorized|Can't get Google credentials|OAuth2 flow requires", msg)
  list(ok = FALSE, auth_problem = auth_problem, message = msg)
}

#' Authenticate googlesheets4 + googledrive from the saved login. Never opens
#' a browser. Returns the account email (invisibly).
gs_connect <- function(email = NULL, quiet = FALSE) {
  sa <- .gs_env("GS_SA_JSON")
  if (!is.null(sa)) {
    sa <- path.expand(sa)
    if (!file.exists(sa)) stop("GS_SA_JSON=", sa, " does not exist.", call. = FALSE)
    tok <- tryCatch(gargle::credentials_service_account(scopes = GS_SCOPE, path = sa),
                    error = function(e) stop("GS_SA_JSON=", sa, " is not a usable service-account key: ",
                                             conditionMessage(e), call. = FALSE))
    if (is.null(tok)) stop("GS_SA_JSON=", sa, " is not a service-account key (no type = \"service_account\" in the JSON).", call. = FALSE)
    googlesheets4::gs4_auth(token = tok)     # bring-your-own token: no fallback to cached user logins
    if (!GS_USES_DRIVE) googledrive::drive_deauth()
    chk <- gs_live_check(tok)
    if (!chk$ok) {
      stop("Service account ", basename(sa),
           if (chk$auth_problem) " was rejected by Google (" else " could not be verified — network problem (",
           chk$message, ").", call. = FALSE)
    }
    if (!quiet) message("[gs_connect] Connected via service account ", basename(sa), " (", GS_SCOPE_LEVEL, ")")
    return(invisible(suppressMessages(googlesheets4::gs4_user())))
  }

  email <- gs_resolve_email(email)
  if (is.null(email)) {
    stop("No Google account configured for this skill yet.\n",
         "Run once (opens a Google sign-in page):  ", GS_SETUP_SH, " auth you@example.com\n",
         "then re-run this script.", call. = FALSE)
  }
  no_login <- function(detail = NULL) {
    stop("No saved Google login for ", email, " with the requested access (", GS_SCOPE_LEVEL, ").\n",
         "Run once (opens a Google sign-in page):  ", GS_SETUP_SH, " auth ", email, "\n",
         "then re-run this script.",
         if (!is.null(detail)) paste0("\n(", detail, ")") else "", call. = FALSE)
  }

  cache <- gs_oauth_cache()
  # rlang_interactive = FALSE: gargle can never start a browser flow from here,
  # even when this file is sourced inside RStudio.
  old <- options(gargle_oauth_cache = cache, rlang_interactive = FALSE)
  on.exit(options(old), add = TRUE)

  logins <- gs_cached_logins(cache)
  bad <- attr(logins, "unreadable")
  if (length(bad)) {
    no_login(paste0("Unreadable token file(s) in ", cache, ": ", paste(basename(bad), collapse = ", "),
                    " — `auth` moves them aside"))
  }
  hit <- logins[logins$email == email & logins$has_scope, , drop = FALSE]
  if (!nrow(hit)) no_login()
  email <- hit$email[[1]]      # exactly as gargle named the cache file

  res <- tryCatch(googlesheets4::gs4_auth(email = email, scopes = GS_SCOPE, cache = cache),
                  error = function(e) e)
  if (inherits(res, "error")) no_login(conditionMessage(res))

  # Least privilege: below the Drive levels, googledrive must NOT quietly pick up
  # some other cached token (for example a full-Drive one from an older install).
  if (!GS_USES_DRIVE) googledrive::drive_deauth()

  chk <- gs_live_check(googlesheets4::gs4_token())
  if (!chk$ok) {
    if (chk$auth_problem) {
      stop("The saved Google login for ", email, " no longer works (revoked or expired: ",
           chk$message, ").\n",
           "Run once to sign in again:  ", GS_SETUP_SH, " auth ", email, call. = FALSE)
    }
    stop("Could not reach Google to verify the saved login for ", email, " (", chk$message, ").\n",
         "The saved login is fine — do NOT sign in again. Check network/VPN/proxy; if only some ",
         "googleapis hosts fail to resolve, run httr::set_config(httr::config(ipresolve = 1L)) ",
         "before gs_connect() (see references/auth.md, 'Network quirk').", call. = FALSE)
  }

  if (!quiet) message("[gs_connect] Connected as ", email, " (", GS_SCOPE_LEVEL, ")")
  invisible(email)
}
