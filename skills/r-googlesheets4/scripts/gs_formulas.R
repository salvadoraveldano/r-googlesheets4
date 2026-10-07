# =============================================================================
# gs_formulas.R — Generic formula builders for Google Sheets
# =============================================================================
#
# Sheets uses commas as argument separators globally, regardless of locale —
# unlike Excel in EU locales where it's semicolon. These helpers build
# `=FORMULA(...)` strings that work everywhere Sheets is supported.
# =============================================================================

#' Strip the leading `=` from a formula string.
#'
#' Formula builders return `=SUMIFS(...)`. When combining two builders into
#' one cell formula via `glue("={f_a()}+{f_b()}")`, you'd get
#' `==SUMIFS(...)+==SUMIFS(...)`. Use `fraw()` to drop the leading `=` from
#' inner builders:
#'   `glue("={fraw(f_a(...))}+{fraw(f_b(...))}")`
fraw <- function(f) sub("^=", "", as.character(f))

#' Build a SUMIFS formula from a sum-range and a list of (criteria_range,
#' criteria) pairs. Quotes any character criteria automatically.
#'
#' @param sum_range      e.g. "People!C:C"
#' @param criteria_pairs named list: list("People!A:A" = "Technology", ...)
#'                       OR a list of length-2 character vectors.
#' @return character — `=SUMIFS(...)`
#'
#' @examples
#' f_sumifs("People!C:C", list("People!A:A" = "Technology"))
#' # → '=SUMIFS(People!C:C,People!A:A,"Technology")'
#'
#' f_sumifs("OPEX!M:M",
#'          list("OPEX!C:C" = "Sales",
#'               "OPEX!I:I" = "SaaS"))
#' # → '=SUMIFS(OPEX!M:M,OPEX!C:C,"Sales",OPEX!I:I,"SaaS")'
f_sumifs <- function(sum_range, criteria_pairs) {
  parts <- character()
  if (!is.null(names(criteria_pairs)) && all(nzchar(names(criteria_pairs)))) {
    for (cr in names(criteria_pairs)) {
      val <- criteria_pairs[[cr]]
      parts <- c(parts, cr, quote_criteria(val))
    }
  } else {
    for (p in criteria_pairs) {
      parts <- c(parts, p[[1L]], quote_criteria(p[[2L]]))
    }
  }
  sprintf("=SUMIFS(%s,%s)", sum_range, paste(parts, collapse = ","))
}

# Internal: wrap character literals in double-quotes; pass cell refs through.
quote_criteria <- function(x) {
  x <- as.character(x)
  # Heuristic: starts with $, A1-letter+digit, or is purely numeric → cell/number, no quotes.
  is_ref_or_num <- grepl('^(\\$|[A-Za-z]+\\$?[0-9]|[<>=!][<>=]?[0-9.\\-])', x) ||
                   grepl('^-?[0-9.]+$', x)
  if (is_ref_or_num) x else sprintf('"%s"', x)
}

#' Safe-division formula: returns "" if denominator is zero.
#' Use to prevent #DIV/0! in margin / ratio cells.
f_safe_div <- function(numerator_cell, denom_cell) {
  sprintf('=IF(%s=0,"",%s/%s)', denom_cell, numerator_cell, denom_cell)
}

#' Wrap an expression in IFERROR with a fallback.
f_iferror <- function(expr, fallback = '""') {
  expr <- fraw(expr)
  sprintf("=IFERROR(%s,%s)", expr, fallback)
}

#' Build a formula that references one or more named ranges. Useful for
#' driver-based models where assumption cells are named (`arpu`, `tax_rate`).
#'
#' @param expr character — formula body using {name1}, {name2} placeholders
#' @param ...  named values to interpolate
#'
#' @examples
#' f_named("={cell}*{driver}", cell = "B5", driver = "arpu")
#' # → "=B5*arpu"
f_named <- function(expr, ...) {
  args <- list(...)
  for (nm in names(args)) {
    expr <- gsub(sprintf("\\{%s\\}", nm), as.character(args[[nm]]), expr, fixed = FALSE)
  }
  if (!startsWith(expr, "=")) expr <- paste0("=", expr)
  expr
}

#' SPARKLINE formula. Sheets-only feature (no Excel equivalent).
f_sparkline <- function(range, options = list()) {
  if (length(options) == 0L) return(sprintf('=SPARKLINE(%s)', range))
  opt_str <- paste(sprintf('"%s","%s"', names(options), unlist(options)),
                   collapse = ";")
  sprintf('=SPARKLINE(%s, {%s})', range, opt_str)
}

#' QUERY formula — Sheets SQL-like data lookup.
#' @param data_range  e.g. "OPEX!A:M"
#' @param query       SQL-style string (use single quotes for literals inside)
#' @param header      0 = no header, 1 = first row is header, -1 = guess
f_query <- function(data_range, query, header = 0L) {
  query_esc <- gsub('"', '""', query)  # double quotes inside formula
  sprintf('=QUERY(%s,"%s",%d)', data_range, query_esc, header)
}
