# =============================================================================
# gs_buffer.R — Buffered cell writes + reusable style presets
# =============================================================================
#
# When you write many individual cells (formulas, labels, single values), one
# `range_write()` per call burns rate limit and runs slowly. Instead: buffer
# all writes in a private environment, then flush all at once via
# `values.batchUpdate`. Combined with one `batch_format()` call, a typical
# tab build collapses from hundreds of API calls to TWO.
#
# Sourcing order: `gs_helpers.R` first (provides `col_letter`, namespace pin).
# =============================================================================

# Depends on gs_helpers.R for col_letter() and the request_generate pin.
if (!exists("col_letter")) stop("Source gs_helpers.R before gs_buffer.R")

# ── The buffer -------------------------------------------------------------
# Use an environment, not a list — environments are mutable, lists copy on
# modify so changes inside helpers wouldn't persist.

.wb <- new.env(parent = emptyenv())
.wb$data <- list()

#' Buffer a single-cell write. Value can be plain text or a formula starting
#' with `=`. USER_ENTERED on flush means formulas evaluate.
#'
#' @param ss     spreadsheet ref
#' @param sheet  tab name (string)
#' @param row    1-based row
#' @param col    1-based column
#' @param value  string, number, or formula (auto-coerced to character)
write_cell <- function(ss, sheet, row, col, value) {
  cl <- col_letter(col)
  range_str <- sprintf("'%s'!%s%d", sheet, cl, row)
  .wb$data[[length(.wb$data) + 1L]] <- list(
    range  = range_str,
    values = list(list(as.character(value)))
  )
}

#' Flush all buffered writes in ONE values.batchUpdate call.
#'
#' Uses USER_ENTERED so formulas are parsed. Resets the buffer afterwards.
flush_writes <- function(ss) {
  if (length(.wb$data) == 0L) return(invisible(NULL))
  message(sprintf("[flush_writes] %d cell writes…", length(.wb$data)))

  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.values.batchUpdate",
    params = list(
      spreadsheetId    = as.character(ss),
      valueInputOption = "USER_ENTERED",
      data             = .wb$data
    )
  )
  resp <- googlesheets4::request_make(req)

  sc <- httr::status_code(resp)
  if (sc >= 400L) {
    err <- httr::content(resp, as = "text", encoding = "UTF-8")
    message(sprintf("[flush_writes] HTTP %d ERROR: %s", sc, substr(err, 1L, 500L)))
  }
  .wb$data <- list()
  invisible(resp)
}

#' Manually clear the buffer without flushing. Rare — use after a partial
#' build that you want to abort.
clear_writes <- function() {
  .wb$data <- list()
  invisible(NULL)
}

# ── Style presets ----------------------------------------------------------
# Apply STYLE_BODY to the full sheet range FIRST (global default), then
# override with section-specific styles. Last-writer-wins within one batch.

STYLE_BODY <- list(
  font_family = "Arial", font_size = 11,
  valign = "MIDDLE"
)

STYLE_BODY_BOLD <- list(
  font_family = "Arial", font_size = 11, bold = TRUE,
  valign = "MIDDLE"
)

STYLE_TITLE <- list(
  font_family = "Arial", font_size = 18, bold = TRUE,
  halign = "LEFT", valign = "MIDDLE"
)

STYLE_SUBTITLE <- list(
  font_family = "Arial", font_size = 11, italic = TRUE,
  font_color = COL_MUTED_TEXT,
  halign = "LEFT", valign = "MIDDLE"
)

STYLE_SECTION_HEADER <- list(
  font_family = "Arial", font_size = 12, bold = TRUE,
  font_color = COL_WHITE, bg_color = COL_BLACK,  # caller overrides bg_color to brand blue (COL_BRAND)
  halign = "LEFT", valign = "MIDDLE"
)

STYLE_SUBTOTAL    <- list(bold = TRUE, bg_color = COL_BLUE_LIGHT)
STYLE_NET_INCOME  <- list(font_size = 12, bold = TRUE, bg_color = COL_BLUE_LIGHT)
STYLE_REMAINING   <- list(bold = TRUE, bg_color = COL_GREEN_LIGHT)
STYLE_GRAYED_OUT  <- list(font_color = COL_GRAY_TEXT, bg_color = COL_LIGHT_GRAY)
STYLE_PCT_ANNOTATION <- list(italic = TRUE, font_color = COL_MUTED_TEXT)
STYLE_TOTAL       <- list(font_size = 11, bold = TRUE, bg_color = COL_LIGHT_GRAY)

# ── apply_style: preset + overrides ----------------------------------------

#' Apply a style preset to a range, with optional per-call overrides.
#'
#' @param sheet_id  numeric sheetId
#' @param start_row,end_row,start_col,end_col  1-based bounds
#' @param style     list of fmt_cells parameters
#' @param ...       overrides — these win over `style`
#' @return single repeatCell request (drop into `batch_format()`)
apply_style <- function(sheet_id, start_row, end_row, start_col, end_col,
                        style, ...) {
  args <- modifyList(style, list(...))
  do.call(fmt_cells, c(
    list(sheet_id  = sheet_id,
         start_row = start_row, end_row = end_row,
         start_col = start_col, end_col = end_col),
    args
  ))
}

# ── Section header helper (buffered) ---------------------------------------

#' Buffer a section-header cell write AND return the formatting requests.
#'
#' The label gets buffered (call `flush_writes()` later); the merge / style /
#' row-height requests are returned so the caller assembles them with other
#' format requests for one big `batch_format()`.
#'
#' Returns a list of 3 requests — combine with `c()`, not `list()`.
write_section_header <- function(ss, sheet_name, sheet_id, row, label,
                                 start_col = 3L, end_col = 8L,
                                 bg_color  = COL_BLACK,   # override with brand color
                                 fg_color  = COL_WHITE,
                                 font_size = 12L,
                                 row_height = 30L) {
  write_cell(ss, sheet_name, row, start_col, label)
  list(
    fmt_merge(sheet_id, row, row, start_col, end_col),
    apply_style(sheet_id, row, row, start_col, end_col, STYLE_SECTION_HEADER,
                bg_color = bg_color, font_color = fg_color, font_size = font_size),
    fmt_row_height(sheet_id, row, row, row_height)
  )
}
