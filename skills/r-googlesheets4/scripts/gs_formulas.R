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
  # An operator criterion such as ">5" or ">=10" is text, so it gets quoted.
  is_ref_or_num <- grepl('^(\\$|[A-Za-z]+\\$?[0-9])', x) ||
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

#' API colour list(red, green, blue) (0-1 floats, as `hex_to_color()` makes) →
#' "#RRGGBB". The reverse of `hex_to_color()`, for places that want hex text,
#' such as a SPARKLINE `color` option. A channel the API left out counts as 0
#' (it omits zeros), so a colour read back from a sheet works too.
#' @examples
#' color_to_hex(hex_to_color("#2457C5"))
#' # → "#2457C5"
color_to_hex <- function(color) {
  if (!is.list(color)) stop("color_to_hex(): `color` must be list(red, green, blue)", call. = FALSE)
  ch <- function(x) if (is.null(x)) 0L else as.integer(round(x * 255))
  sprintf("#%02X%02X%02X", ch(color$red), ch(color$green), ch(color$blue))
}

#' SPARKLINE formula. Sheets-only feature (no Excel equivalent).
#'
#' Option values keep their R type: numbers and logicals are written bare
#' (`"linewidth",2`), strings are quoted with embedded `"` doubled
#' (`"color","#2457C5"`). Wrap a value in `I()` to write it verbatim, for a cell
#' reference or an expression: `I("$H$5")`, `I('IF(G2>1,"#E5484D","#2457C5")')`.
#'
#' @param range    the data, e.g. "B2:M2" (verbatim)
#' @param options  named list of SPARKLINE options
#' @param iferror  TRUE wraps the result in `IFERROR(..., "")`, so a row with no
#'                 numbers shows an empty cell instead of `#N/A`
#' @examples
#' f_sparkline("B2:M2", list(charttype = "line", linewidth = 2, color = "#2457C5"))
#' # → '=SPARKLINE(B2:M2, {"charttype","line";"linewidth",2;"color","#2457C5"})'
#' f_sparkline("H2", list(charttype = "bar", max = I("$H$1"), color1 = "#18A957"))
#' # → '=SPARKLINE(H2, {"charttype","bar";"max",$H$1;"color1","#18A957"})'
#' f_sparkline("B2:M2", list(color = "#2457C5"), iferror = TRUE)
#' # → '=IFERROR(SPARKLINE(B2:M2, {"color","#2457C5"}),"")'
f_sparkline <- function(range, options = list(), iferror = FALSE) {
  options <- Filter(Negate(is.null), options)   # list(max = NULL) means "not set"
  if (length(options) && (is.null(names(options)) || !all(nzchar(names(options)))))
    stop("f_sparkline(): every option needs a name", call. = FALSE)
  lit <- function(v) {
    if (inherits(v, "AsIs")) return(as.character(v))
    if (is.logical(v)) return(toupper(as.character(v)))
    if (is.numeric(v)) return(format(v, scientific = FALSE, trim = TRUE, digits = 15, decimal.mark = "."))
    sprintf('"%s"', gsub('"', '""', as.character(v), fixed = TRUE))
  }
  f <- if (length(options) == 0L) sprintf('=SPARKLINE(%s)', range) else
    sprintf('=SPARKLINE(%s, {%s})', range,
            paste(sprintf('"%s",%s', names(options), vapply(options, lit, "")), collapse = ";"))
  if (iferror) f_iferror(f) else f
}

#' QUERY formula — Sheets SQL-like data lookup.
#' @param data_range  e.g. "OPEX!A:M"
#' @param query       SQL-style string (use single quotes for literals inside)
#' @param header      0 = no header, 1 = first row is header, -1 = guess
f_query <- function(data_range, query, header = 0L) {
  query_esc <- gsub('"', '""', query)  # double quotes inside formula
  sprintf('=QUERY(%s,"%s",%d)', data_range, query_esc, header)
}
