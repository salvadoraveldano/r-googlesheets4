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
      spreadsheetId    = as.character(googlesheets4::as_sheets_id(ss)),
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
#
# No preset sets a font family: the spreadsheet theme does (THEME_DEFAULT, sent
# with `do.call(fmt_theme_colors, THEME_DEFAULT)` in the first batch), so one
# setting changes the whole file. Sizes are points. Bold is the only weight
# Sheets has; size carries the hierarchy (references/design-principles.md).

STYLE_BODY      <- list(font_size = 10, font_color = COL_INK, valign = "MIDDLE")
STYLE_BODY_BOLD <- list(font_size = 10, font_color = COL_INK, bold = TRUE, valign = "MIDDLE")
STYLE_TITLE     <- list(font_size = 20, bold = TRUE, font_color = COL_INK,
                        halign = "LEFT", valign = "BOTTOM")
STYLE_FINDING   <- list(font_size = 11, italic = FALSE, font_color = COL_TEXT_2,   # one sentence that answers the tab
                        halign = "LEFT", valign = "MIDDLE")
STYLE_SUBTITLE  <- STYLE_FINDING
STYLE_NOTE      <- list(font_size = 9, italic = FALSE, font_color = COL_TEXT_3,    # meta line, source, units
                        halign = "LEFT", valign = "MIDDLE")
STYLE_PCT_ANNOTATION <- STYLE_NOTE
STYLE_SECTION_HEADER <- list(font_size = 12, bold = TRUE, font_color = COL_INK,    # with an ink rule above (fmt_section)
                             bg_color = COL_WHITE, halign = "LEFT", valign = "BOTTOM")
STYLE_HEADER    <- list(font_size = 9, bold = TRUE, font_color = COL_TEXT_2,       # table column headers
                        valign = "BOTTOM", wrap = TRUE)
STYLE_SUBTOTAL  <- list(bold = TRUE, bg_color = COL_WHITE)
STYLE_NET_INCOME <- list(font_size = 10, bold = TRUE, bg_color = COL_WHITE)
STYLE_REMAINING <- list(bold = TRUE, font_color = STATUS$positive$ink, bg_color = COL_WHITE)
STYLE_GRAYED_OUT <- list(font_color = COL_TEXT_3, italic = TRUE, bg_color = COL_SURFACE)  # 5.3:1
STYLE_TOTAL     <- list(font_size = 10, bold = TRUE, bg_color = COL_SURFACE)       # the total COLUMN
STYLE_INPUT     <- list(font_color = COL_INPUT_FG, bg_color = COL_INPUT_BG)        # every typed-in cell
STYLE_CONTROL   <- list(font_size = 11, bold = TRUE, font_color = COL_INPUT_FG,    # the one picker on a tab
                        bg_color = COL_INPUT_BG, halign = "CENTER")
STYLE_CHIP      <- list(font_size = 9, bold = TRUE, font_color = COL_TEXT_3,       # status words; fmt_status() colours them
                        halign = "CENTER")

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
#' row-height / top-rule requests are returned so the caller assembles them with
#' other format requests for one big `batch_format()`. New builds use
#' `fmt_section()`, which does not merge.
#'
#' Returns a list of 4 requests — combine with `c()`, not `list()`.
write_section_header <- function(ss, sheet_name, sheet_id, row, label,
                                 start_col = 3L, end_col = 8L,
                                 bg_color  = COL_WHITE,
                                 fg_color  = COL_INK,
                                 font_size = 12L,
                                 row_height = 30L) {
  write_cell(ss, sheet_name, row, start_col, label)
  list(
    fmt_merge(sheet_id, row, row, start_col, end_col),
    apply_style(sheet_id, row, row, start_col, end_col, STYLE_SECTION_HEADER,
                bg_color = bg_color, font_color = fg_color, font_size = font_size),
    fmt_row_height(sheet_id, row, row, row_height),
    fmt_borders(sheet_id, row, row, start_col, end_col, top = BORDER_INK)
  )
}

# ── Layout helpers: the design system's components -------------------------
# Each returns a LIST of requests (combine with `c()`); none writes values or
# merges cells. Write the text with write_cell() / write_block(). Rows and
# columns are 1-based. Recipes: references/design-principles.md.

#' Base layer for one tab: body style, gridlines by kind, 16 px gutter columns,
#' the title block rows, frozen panes and the tab colour.
#'
#' @param end_row,end_col  extent of the tab's styled area
#' @param kind      "dashboard" / "model": gridlines off; "data": gridlines on,
#'                  row 1 frozen, no title block
#' @param widths    pixel widths of the content columns from B; column A and
#'                  the column after the last width become 16 px gutters
#' @param title_row row of the title (row above: 12 px spacer); the next two
#'                  rows are the finding (22 px) and the meta line (18 px).
#'                  Styles go on column B. NULL skips the title block; a data
#'                  tab skips it unless you pass `title_row`.
#' @param inputs    TRUE colours the tab blue: "this tab holds inputs"
fmt_tab_base <- function(sheet_id, end_row, end_col, kind = c("dashboard", "model", "data"),
                         widths = NULL, title_row = 2L, inputs = FALSE,
                         freeze_rows = NULL, freeze_cols = NULL) {
  kind <- match.arg(kind)
  out <- list(apply_style(sheet_id, 1L, end_row, 1L, end_col, STYLE_BODY),
              fmt_gridlines(sheet_id, show = kind == "data"))
  if (!is.null(widths)) out <- c(out, fmt_col_widths(sheet_id, c(16, widths, 16)))
  else if (kind != "data") out <- c(out, list(fmt_col_width(sheet_id, 1L, 1L, 16L)))
  if (kind == "data") { if (missing(title_row)) title_row <- NULL; freeze_rows <- freeze_rows %||% 1L }
  if (!is.null(title_row)) {
    r <- as.integer(title_row)
    if (r > 1L) out <- c(out, list(fmt_row_height(sheet_id, r - 1L, r - 1L, 12L)))
    out <- c(out, list(
      apply_style(sheet_id, r, r, 2L, 2L, STYLE_TITLE),         fmt_row_height(sheet_id, r, r, 36L),
      apply_style(sheet_id, r + 1L, r + 1L, 2L, 2L, STYLE_FINDING), fmt_row_height(sheet_id, r + 1L, r + 1L, 22L),
      apply_style(sheet_id, r + 2L, r + 2L, 2L, 2L, STYLE_NOTE),    fmt_row_height(sheet_id, r + 2L, r + 2L, 18L)))
  }
  if (!is.null(freeze_rows) || !is.null(freeze_cols))
    out <- c(out, list(fmt_freeze(sheet_id, rows = freeze_rows %||% 0L, cols = freeze_cols %||% 0L)))
  if (isTRUE(inputs)) out <- c(out, list(fmt_tab_color(sheet_id, COL_INPUT_FG)))
  out
}

#' A section: a 12 pt bold heading over an ink rule, and (header = TRUE) the
#' table's column-header row under it: 9 pt bold grey, a #999 rule below,
#' numeric columns right-aligned.
#'
#' @param row           the heading row; the header row is `row + 1`
#' @param heading       FALSE = only the column-header row, on `row` itself (a
#'                      table right under the tab title needs no heading)
#' @param numeric_cols  absolute column indices whose header sits right
#' @param meta_col      a column on the heading row for a short right-aligned
#'                      note ("3 of 9 over", "$ thousands")
fmt_section <- function(sheet_id, row, start_col, end_col, header = TRUE,
                        numeric_cols = integer(0), meta_col = NULL, heading = TRUE) {
  if (!isTRUE(heading)) {
    if (!isTRUE(header)) stop("fmt_section(): heading = FALSE needs header = TRUE", call. = FALSE)
    row <- row - 1L
    out <- list()
  } else out <- list(apply_style(sheet_id, row, row, start_col, end_col, STYLE_SECTION_HEADER),
                     fmt_row_height(sheet_id, row, row, 30L),
                     fmt_borders(sheet_id, row, row, start_col, end_col, top = BORDER_INK))
  if (!is.null(meta_col) && isTRUE(heading))
    out <- c(out, list(apply_style(sheet_id, row, row, meta_col, meta_col, STYLE_NOTE,
                                   bold = FALSE, halign = "RIGHT", valign = "BOTTOM")))
  if (isTRUE(header)) {
    h <- row + 1L
    out <- c(out, list(apply_style(sheet_id, h, h, start_col, end_col, STYLE_HEADER, halign = "LEFT"),
                       fmt_row_height(sheet_id, h, h, 26L),
                       fmt_borders(sheet_id, h, h, start_col, end_col, bottom = BORDER_STRONG)),
             lapply(numeric_cols, function(c) fmt_cells(sheet_id, h, h, c, c, halign = "RIGHT")))
  }
  out
}

#' Table body: 10 pt ink, faint row rules, numbers right-aligned in their
#' format, optional subtotal rows (bold, #999 rule above), total rows (bold,
#' ink rule above, double ink rule below) and a total column (bold on the
#' surface grey, #999 rule on its left).
#'
#' @param numeric_cols  absolute column indices; get `numfmt` and RIGHT
#' @param numfmt        one NUMFMT_* for every numeric column, or a list with one
#'                      per numeric column (NULL entries keep the cell's format)
#' @param density       "model" = 24 px rows, "dashboard" = 28 px rows
#' @param total_col     one or more columns that hold totals
fmt_table_body <- function(sheet_id, start_row, end_row, start_col, end_col,
                           numeric_cols = integer(0), numfmt = NULL,
                           density = c("model", "dashboard"),
                           subtotal_rows = integer(0), total_rows = integer(0), total_col = NULL) {
  density <- match.arg(density)
  if (!is.null(numfmt) && !is.null(numfmt$type)) numfmt <- rep(list(numfmt), length(numeric_cols))
  if (length(numfmt) && length(numfmt) != length(numeric_cols))
    stop("fmt_table_body(): `numfmt` must be one format or one per numeric column", call. = FALSE)
  out <- list(apply_style(sheet_id, start_row, end_row, start_col, end_col, STYLE_BODY),
              fmt_row_height(sheet_id, start_row, end_row, if (density == "model") 24L else 28L),
              fmt_borders(sheet_id, start_row, end_row, start_col, end_col,
                          inner_h = BORDER_SUBTLE, bottom = BORDER_SUBTLE))
  for (k in seq_along(numeric_cols)) {
    c <- numeric_cols[k]
    out <- c(out, list(fmt_cells(sheet_id, start_row, end_row, c, c, halign = "RIGHT",
                                 numfmt = if (length(numfmt)) numfmt[[k]] else NULL)))
  }
  for (tc in total_col)
    out <- c(out, list(apply_style(sheet_id, start_row, end_row, tc, tc, STYLE_TOTAL),
                       fmt_borders(sheet_id, start_row, end_row, tc, tc, left = BORDER_STRONG)))
  for (r in subtotal_rows)
    out <- c(out, list(fmt_cells(sheet_id, r, r, start_col, end_col, bold = TRUE),
                       fmt_borders(sheet_id, r, r, start_col, end_col, top = BORDER_STRONG)))
  for (r in total_rows)
    out <- c(out, list(fmt_cells(sheet_id, r, r, start_col, end_col, bold = TRUE),
                       fmt_row_height(sheet_id, r, r, 28L),
                       fmt_borders(sheet_id, r, r, start_col, end_col, top = BORDER_INK, bottom = BORDER_DOUBLE)))
  out
}

#' KPI strip: three rows (label 20 px, value 44 px, delta 20 px) with no tiles,
#' fills or sparklines. The lead value is 28 pt, the others 18 pt, all regular
#' weight, left-aligned and on one baseline. An ink rule above and a faint rule
#' below run from the first KPI column to `rule_end_col`. Each delta is coloured
#' by its KPI's good direction: green for a good change, red for a bad one.
#'
#' @param row     the label row; values are row + 1, deltas row + 2
#' @param cols    one column per KPI, left to right
#' @param lead    the column of the figure that answers the tab's question
#' @param good    "up", "down" or "none" per KPI (recycled): a cost is "down"
#' @param value_numfmt,delta_numfmt  one NUMFMT_* or a list with one per KPI
#'                (NULL entries keep the cell's format, e.g. text sub-values)
fmt_kpi_strip <- function(sheet_id, row, cols, lead = cols[1L], good = "up",
                          value_numfmt = NULL, delta_numfmt = NUMFMT_DELTA_PCT,
                          rule_end_col = max(cols)) {
  n <- length(cols)
  good <- rep_len(good, n)
  if (!all(good %in% c("up", "down", "none")))
    stop("fmt_kpi_strip(): `good` must be \"up\", \"down\" or \"none\"", call. = FALSE)
  per <- function(x) if (is.null(x)) vector("list", n) else if (!is.null(x$type)) rep(list(x), n) else rep_len(x, n)
  vf <- per(value_numfmt); df <- per(delta_numfmt)
  r1 <- row; r2 <- row + 1L; r3 <- row + 2L
  out <- list(fmt_row_height(sheet_id, r1, r1, 20L), fmt_row_height(sheet_id, r2, r2, 44L),
              fmt_row_height(sheet_id, r3, r3, 20L))
  for (k in seq_len(n)) {
    c <- cols[k]
    out <- c(out, list(
      apply_style(sheet_id, r1, r1, c, c, STYLE_NOTE, valign = "BOTTOM"),
      fmt_cells(sheet_id, r2, r2, c, c, font_size = if (c == lead) 28 else 18, bold = FALSE,
                font_color = COL_INK, halign = "LEFT", valign = "BOTTOM", numfmt = vf[[k]]),
      fmt_cells(sheet_id, r3, r3, c, c, font_size = 9, bold = FALSE, font_color = COL_TEXT_3,
                halign = "LEFT", valign = "TOP", numfmt = df[[k]])))
    if (good[k] != "none") {
      up <- if (good[k] == "up") COL_POSITIVE else COL_NEGATIVE
      dn <- if (good[k] == "up") COL_NEGATIVE else COL_POSITIVE
      # The two rules never overlap (> 0 and < 0), so their priority does not matter.
      out <- c(out, list(fmt_cond_number(sheet_id, r3, r3, c, c, value = 0, op = "greater", font_color = up),
                         fmt_cond_number(sheet_id, r3, r3, c, c, value = 0, op = "less", font_color = dn)))
    }
  }
  c(out, list(fmt_borders(sheet_id, r1, r3, min(cols), rule_end_col, top = BORDER_INK, bottom = BORDER_SUBTLE)))
}

#' Status chips by conditional formatting: each state's word gets its pale fill
#' and dark ink from STATUS. Leave "fine" states out, so colour shows only on
#' the rows at risk. A badge (one cell) works the same way, e.g.
#' `states = c("✓" = "positive", "✕" = "negative"), op = "starts_with"`; size
#' the cell to its text, because text that spills past the cell has no fill.
#'
#' @param states  named character: word = one of names(STATUS), in priority order
#' @param index   priority of the first rule; the next ones follow (first listed wins)
fmt_status <- function(sheet_id, start_row, end_row, start_col, end_col, states,
                       op = c("equals", "starts_with", "contains"), index = 0L) {
  op <- match.arg(op)
  if (!is.character(states) || is.null(names(states)) || any(!nzchar(names(states))))
    stop("fmt_status(): `states` must be a named character vector, e.g. c(Over = \"negative\")", call. = FALSE)
  bad <- setdiff(states, names(STATUS))
  if (length(bad))
    stop("fmt_status(): unknown state colour(s) ", paste(bad, collapse = ", "), "; use ",
         paste(names(STATUS), collapse = ", "), call. = FALSE)
  c(list(apply_style(sheet_id, start_row, end_row, start_col, end_col, STYLE_CHIP)),
    lapply(seq_along(states), function(k) {
      s <- STATUS[[states[[k]]]]
      fmt_cond_text(sheet_id, start_row, end_row, start_col, end_col, op = op, text = names(states)[k],
                    bg_color = s$fill, font_color = s$ink, index = as.integer(index) + k - 1L)
    }))
}
