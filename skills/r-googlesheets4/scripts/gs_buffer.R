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
#   write_cell()   buffer one cell          write_block()  buffer a whole rectangle
#   flush_writes() send the buffer          (strict = TRUE stops on an HTTP error)
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

# Text that looks like a signed number ("-5", "+1,200.50", "-$5", "-5%", "+1e3"):
# left alone so USER_ENTERED turns it into a number, as the caller meant.
.NUM_LIKE <- "^[-+]\\s*[$\u20ac\u00a3]?\\.?[0-9][0-9.,]*(e[-+]?[0-9]+)?%?$"

# One cell's value, in the form it is sent to Google.
#   * numbers and logicals are sent as JSON numbers / booleans, NOT as text.
#     Text is parsed by Sheets: as.character(2e6) = "2e+06" lands with an
#     "2.00E+06" number format, and in a decimal-comma locale (for example
#     de_DE) the text "1234.5" is misread (it was stored as -243129). A JSON
#     number is neither.
#   * NA / NaN become "" (an empty cell).
#   * text starting with `=` is a formula (that is the point of USER_ENTERED).
#   * any other text is a literal. Under USER_ENTERED a leading `+` becomes a
#     formula ("+abc" -> #NAME?) and a leading `'` is swallowed as the Sheets
#     text marker, so text starting with + - @ or ' gets ONE extra `'` prefix
#     (Sheets removes it again; it is not stored). A string that is a signed
#     number is the exception: it stays a number. `as_text = TRUE` forces the
#     prefix on any text, to keep "00123", "1/2" or "TRUE" as text.
.cell_value <- function(v, as_text = FALSE) {
  if (length(v) != 1L) stop("A cell holds exactly one value (got ", length(v), ").", call. = FALSE)
  if (is.na(v)) return("")
  if (is.numeric(v)) {
    if (!is.finite(v)) stop("Cannot write a non-finite number: ", v, call. = FALSE)
    return(v)
  }
  if (is.logical(v)) return(v)
  v <- as.character(v)
  if (grepl(.NUM_LIKE, v, ignore.case = TRUE) && !isTRUE(as_text))
    return(sub("^\\+\\s*", "", v))     # "+5" would be stored as the formula +5: send "5"
  if (isTRUE(as_text) || grepl("^['@+-]", v)) v <- paste0("'", v)
  v
}

# Queue one ValueRange (a list of rows of cell values) at (row, col).
.queue_range <- function(sheet, row, col, rows) {
  nr <- length(rows); nc <- length(rows[[1L]])
  if (col + nc - 1L > 702L) stop("Column ", col + nc - 1L, " is past ZZ, the last column col_letter() names.", call. = FALSE)
  range_str <- sprintf("'%s'!%s%d:%s%d", gsub("'", "''", sheet),   # a quote in a tab name is doubled
                       col_letter(col), row, col_letter(col + nc - 1L), row + nr - 1L)
  .wb$data[[length(.wb$data) + 1L]] <- list(range = range_str, values = rows)
  invisible(NULL)
}

#' Buffer a single-cell write. A string starting with `=` is a formula
#' (USER_ENTERED on flush means formulas evaluate). See `.cell_value()` above for
#' how numbers (sent as real numbers, never as "2e+06" text) and text starting
#' with + - @ or ' are handled.
#'
#' @param ss     spreadsheet ref
#' @param sheet  tab name (string; a `'` in the name is escaped for you)
#' @param row    1-based row
#' @param col    1-based column
#' @param value  one number, logical, string or formula; NA writes an empty cell
#' @param as_text  TRUE to store a string as text even if Sheets would turn it
#'                 into a number, date, boolean or formula ("00123", "1/2")
write_cell <- function(ss, sheet, row, col, value, as_text = FALSE) {
  .queue_range(sheet, row, col, list(list(.cell_value(value, as_text))))
}

#' Buffer a whole rectangle as ONE range entry (one entry in the flush instead
#' of one per cell: a 2,000-cell table is 1 entry, not 2,000). Each cell is
#' handled exactly like `write_cell()`.
#'
#' @param x  matrix or data.frame (column names are NOT written: bind a header
#'           row yourself, for example `rbind(hdr, body)`); a plain vector is
#'           written as one column. `NA` cells become empty cells.
#' @param as_text  as in `write_cell()`, applied to every text cell
#' @examples
#' write_block(ss, "Data", 1, 1, rbind(c("Item", "Qty")))                       # header row
#' write_block(ss, "Data", 2, 1, data.frame(item = c("a", "b"), qty = c(2, 3))) # typed columns
#' # cbind(c("a", "b"), c(2, 3)) would turn the numbers into text: prefer a data.frame
write_block <- function(ss, sheet, row, col, x, as_text = FALSE) {
  if (!is.data.frame(x)) x <- as.matrix(x)
  if (nrow(x) == 0L || ncol(x) == 0L) return(invisible(NULL))
  # ponytail: one R call per cell; fine to ~1e5 cells, vectorise by column type if a build needs more
  rows <- lapply(seq_len(nrow(x)), function(i)
    lapply(seq_len(ncol(x)), function(j) .cell_value(x[[i, j]], as_text)))
  .queue_range(sheet, row, col, rows)
}

#' Flush all buffered writes in ONE values.batchUpdate call.
#'
#' Uses USER_ENTERED so formulas are parsed.
#'
#' The buffer is cleared as soon as Google answers, whether the answer is a
#' success or an HTTP error: values.batchUpdate is all-or-nothing, so after an
#' error NOTHING of that batch was written, and request_make() has already
#' retried 429 and 500/502/503 with backoff (a 504 is not retried), so an error
#' that arrives here is final. Fix the cause and queue the writes again. If no answer arrives at all (network
#' error), the buffer is kept and `flush_writes()` can simply be called again.
#'
#' By default an HTTP error is only logged with `message()`, like `batch_format()`;
#' pass `strict = TRUE` to `stop()` on HTTP >= 400 instead (use it in build
#' scripts, a logged 400 leaves empty tabs and scrolls by unnoticed).
#'
#' @param ss      spreadsheet ref
#' @param strict  if TRUE, stop() on HTTP >= 400 instead of only logging
#' @return invisible httr response (NULL when the buffer was empty)
flush_writes <- function(ss, strict = FALSE) {
  if (length(.wb$data) == 0L) return(invisible(NULL))
  message(sprintf("[flush_writes] %d range writes…", length(.wb$data)))

  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.values.batchUpdate",
    params = list(
      spreadsheetId    = as.character(ss),
      valueInputOption = "USER_ENTERED",
      data             = .wb$data
    )
  )
  resp <- googlesheets4::request_make(req)
  .wb$data <- list()    # Google answered: the batch is spent (see above)

  sc <- httr::status_code(resp)
  if (sc >= 400L) {
    err <- httr::content(resp, as = "text", encoding = "UTF-8")
    msg <- sprintf("[flush_writes] HTTP %d ERROR: %s", sc, substr(err, 1L, 500L))
    if (isTRUE(strict)) stop(msg, call. = FALSE) else message(msg)
  }
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
#' @param ...       overrides — these win over `style`; `NULL` drops that
#'                  property from the preset. How a later call treats text
#'                  properties set earlier (merge vs reset) is decided by the
#'                  field masks `fmt_cells()` builds, not here.
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
