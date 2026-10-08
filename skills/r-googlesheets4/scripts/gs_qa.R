# =============================================================================
# gs_qa.R — Pre-build and post-build QA helpers
# =============================================================================
#
# Catches the failure class where content correctness checks pass but the
# rendered view is broken: cells with the right value in a hidden column,
# charts whose source range overlaps a hidden col (silent placeholder fail),
# subtle formatting differences when regenerating a reference tab.
#
# Sourcing order: `gs_helpers.R` first.
# =============================================================================

if (!exists("request_generate")) stop("Source gs_helpers.R before gs_qa.R")

# ── Locale-safe date formatting --------------------------------------------

#' Format a date in English regardless of `LC_TIME`. Wraps and restores the
#' user's prior locale so other code is unaffected.
safe_locale_date <- function(d = Sys.Date(), fmt = "%B %d, %Y") {
  old <- Sys.getlocale("LC_TIME")
  on.exit(Sys.setlocale("LC_TIME", old), add = TRUE)
  Sys.setlocale("LC_TIME", "C")
  format(d, fmt)
}

# ── Reading: robust numeric parsing ----------------------------------------

#' Parse numbers out of cells read back as TEXT (currency, thousands commas,
#' percent, stray spaces). `as.numeric(gsub("[, ]", "", x))` returns NA on a
#' leading "$"; this strips everything except digits, dot and minus.
#' Vectorized. NB: leading-minus only — accounting parentheses "(100)" lose
#' their sign, so normalize those first if your source uses them.
#'   parse_num(c("$1,234.56", "-$100", "12.5%")) -> 1234.56  -100  12.5
parse_num <- function(x) suppressWarnings(as.numeric(gsub("[^0-9.-]", "", as.character(x))))

# ── Export a tab to PDF (offline visual QA, no MCP) -------------------------

#' Export ONE tab to a local PDF for visual inspection when a render-and-score
#' tool can't reach the live sheet (headless / CI / MCP unavailable). Uses the
#' active googlesheets4 OAuth token against the Drive export endpoint.
#' NB: gs4_token() is already an httr config — pass it straight to GET(),
#' never wrap it in httr::config()/add_headers().
#' The export endpoint rate-limits bursts (HTTP 429) and gargle's auto-retry
#' does NOT cover it (bare httr::GET), so retry here; when looping over many
#' tabs also Sys.sleep(~10) between calls.
#' @return the output path (invisibly). Stops on HTTP error.
export_sheet_as_pdf <- function(ss, sheet_name, path,
                                extra = "&portrait=false&size=A4&fitw=true&gridlines=false") {
  ss_id <- as.character(ss)
  gid   <- get_sheet_id(ss, sheet_name)
  url   <- sprintf("https://docs.google.com/spreadsheets/d/%s/export?format=pdf&gid=%s%s",
                   ss_id, gid, extra)
  for (try_i in 1:5) {
    resp <- httr::GET(url, googlesheets4::gs4_token(),
                      httr::write_disk(path, overwrite = TRUE))
    if (httr::status_code(resp) != 429L) break
    message(sprintf("[export_sheet_as_pdf] 429 rate-limited, retry %d in %ds", try_i, 15 * try_i))
    Sys.sleep(15 * try_i)
  }
  if (httr::status_code(resp) %in% c(401L, 403L)) {
    unlink(path)
    stop("PDF export was refused (HTTP ", httr::status_code(resp), ") at access level '",
         if (exists("GS_SCOPE_LEVEL")) GS_SCOPE_LEVEL else "unknown", "'. If this level cannot export, ask ",
         "the user to approve the narrowest fix: GS_SCOPE_LEVEL=export ",
         "bash scripts/gs_setup.sh auth <email>, then set GS_SCOPE_LEVEL=export for the script.", call. = FALSE)
  }
  httr::stop_for_status(resp)
  message(sprintf("[export_sheet_as_pdf] %s -> %s (%d KB)", sheet_name, path,
                  round(file.info(path)$size / 1024)))
  invisible(path)
}

# ── Visibility audits ------------------------------------------------------

#' Find the first non-hidden column index. Cell content placed in `A1` looks
#' fine via `read_sheet()` but appears blank to the user when col A is hidden
#' — typically inherited from a `sheet_copy()` source tab.
first_visible_col <- function(ss_id, sheet_id, max_check = 26L) {
  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.get",
    params = list(spreadsheetId = ss_id,
                  fields = "sheets(properties(sheetId),data(columnMetadata(hiddenByUser)))")
  )
  resp <- googlesheets4::request_make(req)
  body <- httr::content(resp, as = "parsed")
  for (s in body$sheets) {
    if (!isTRUE(s$properties$sheetId == sheet_id)) next
    cols <- s$data[[1L]]$columnMetadata
    for (i in seq_len(min(max_check, length(cols)))) {
      if (!isTRUE(cols[[i]]$hiddenByUser)) return(i)
    }
  }
  1L
}

#' Audit a merged range: returns TRUE iff at least one column in the merge
#' is visible AND the visible columns sum to at least `min_visible_px`.
audit_merge <- function(ss_id, sheet_id, start_col, end_col,
                        min_visible_px = 80L) {
  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.get",
    params = list(spreadsheetId = ss_id,
                  fields = "sheets(properties(sheetId),data(columnMetadata(pixelSize,hiddenByUser)))")
  )
  resp <- googlesheets4::request_make(req)
  body <- httr::content(resp, as = "parsed")
  for (s in body$sheets) {
    if (!isTRUE(s$properties$sheetId == sheet_id)) next
    cols <- s$data[[1L]]$columnMetadata
    visible_widths <- vapply(start_col:end_col, function(i) {
      cm <- cols[[i]]
      if (isTRUE(cm$hiddenByUser)) 0L
      else as.integer(cm$pixelSize %||% 100L)
    }, integer(1L))
    return(sum(visible_widths) >= min_visible_px)
  }
  FALSE
}

#' Audit charts: warns for any chart whose domain or series source columns
#' overlap `hiddenByUser=TRUE` columns. Such charts render as the empty
#' placeholder ("Add a series to start visualizing your data") with no
#' error response. This audit catches most cases; compare the series count you
#' read back with the number you built (see below).
#'
#' Each source is checked against the hidden columns of the tab it READS FROM
#' (its own sheetId), so a Summary chart fed by a model tab is judged on the
#' model tab's columns. Covers basic, waterfall and pie/doughnut charts; other
#' chart types are skipped.
#'
#' Seen live: while columns are hidden, the spec Sheets returns for a basic or
#' waterfall chart lists fewer series than the chart holds (they all return on
#' unhide), so a series in a hidden column may not show up here. A chart left
#' with no series at all (the placeholder) is flagged for that reason. Check
#' the series count you read back against the number you built.
#' @param sheet_id audit charts sitting on this tab; NULL (default) = every tab
#' @return the warning messages, invisibly (each is also raised as a warning)
audit_chart_sources <- function(ss_id, sheet_id = NULL) {
  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.get",
    params = list(
      spreadsheetId = ss_id,
      fields = paste0(
        "sheets(properties(sheetId,title),",
        "data(columnMetadata(hiddenByUser)),",
        "charts(spec(title,",
        "basicChart(domains(domain(sourceRange)),series(series(sourceRange))),",
        "waterfallChart(domain(data(sourceRange)),series(data(sourceRange))),",
        "pieChart(domain(sourceRange),series(sourceRange)))))"
      )
    )
  )
  resp <- googlesheets4::request_make(req)
  httr::stop_for_status(resp)          # an error body must not pass as "no warnings"
  body <- httr::content(resp, as = "parsed")
  # The API omits a zero sheetId / startIndex, so default them to 0.
  sid_of <- function(s) s$properties$sheetId %||% 0L
  hidden <- lapply(body$sheets, function(s) {
    cm <- if (length(s$data)) s$data[[1L]]$columnMetadata else list()
    vapply(cm, function(c) isTRUE(c$hiddenByUser), logical(1L))
  })
  names(hidden) <- vapply(body$sheets, function(s) as.character(sid_of(s)), "")
  tab <- vapply(body$sheets, function(s) s$properties$title %||% "", "")
  names(tab) <- names(hidden)

  warnings_found <- list()
  check <- function(chart_title, host, role, data) {
    for (src in data$sourceRange$sources %||% list()) {
      key <- as.character(src$sheetId %||% 0L)
      h <- hidden[[key]]
      if (is.null(h)) next
      cols <- ((src$startColumnIndex %||% 0L) + 1L):(src$endColumnIndex %||% length(h))
      cols <- cols[cols >= 1L & cols <= length(h)]      # beyond the grid: nothing to hide
      bad <- cols[h[cols]]
      if (length(bad)) {
        msg <- sprintf("[chart QA] '%s' on '%s': %s reads hidden cols %s of tab '%s'",
                       chart_title, host, role,
                       paste(vapply(bad, col_letter, ""), collapse = ","), tab[[key]])
        warning(msg, call. = FALSE)
        warnings_found[[length(warnings_found) + 1L]] <<- msg
      }
    }
  }
  for (s in body$sheets) {
    if (!is.null(sheet_id) && !isTRUE(sid_of(s) == sheet_id)) next
    host <- s$properties$title %||% ""
    for (ch in s$charts %||% list()) {
      ttl <- ch$spec$title %||% "(untitled)"
      b <- ch$spec$basicChart; w <- ch$spec$waterfallChart; p <- ch$spec$pieChart
      for (d in b$domains %||% list()) check(ttl, host, "domain", d$domain)
      for (x in b$series %||% list())  check(ttl, host, "series", x$series)
      check(ttl, host, "domain", w$domain$data)
      for (x in w$series %||% list())  check(ttl, host, "series", x$data)
      # While columns are hidden Sheets returns fewer series than the chart holds,
      # so the loops above can miss them; a chart with none left is the placeholder.
      if ((!is.null(b) && !length(b$series)) || (!is.null(w) && !length(w$series))) {
        msg <- sprintf("[chart QA] '%s' on '%s': no series left (its series read hidden columns, or none were set)",
                       ttl, host)
        warning(msg, call. = FALSE)
        warnings_found[[length(warnings_found) + 1L]] <- msg
      }
      check(ttl, host, "domain", p$domain)
      check(ttl, host, "series", p$series)
    }
  }
  invisible(warnings_found)
}

# ── Clear values, keep everything else --------------------------------------

#' Clear the VALUES of a range or a whole tab and keep the rest: number
#' formats, fills, borders, data validation and notes stay. One `values.clear`
#' call. Use it to blank inputs before a test or a refill without losing the
#' formatting you built.
#'
#' The trap it avoids: `googlesheets4::range_clear()` defaults to
#' `reformat = TRUE`, which wipes the formatting along with the values (pass
#' `reformat = FALSE` to keep it; this helper never touches formatting).
#'
#' It cannot touch another tab: the tab is always part of the range. A string
#' without `!` is read as a tab NAME (a whole tab, quoted for you so a tab
#' called "Q1" is not taken for cell Q1). A string with `!` is used as given, so
#' quote a tab name that has spaces or symbols yourself. A bare "A1:F20" is
#' refused by the API (no such tab) rather than clearing the first tab.
#'
#' @param ss              spreadsheet id or object
#' @param range_or_sheet  "Data" (whole tab) or "Data!A1:F20" / "'My Tab'!A1:F20"
#' @return the cleared range as the API reports it (invisibly)
#' @examples
#' gs_clear_values(ss, "Inputs")             # every value on the tab
#' gs_clear_values(ss, "Inputs!B2:B20")      # one range
gs_clear_values <- function(ss, range_or_sheet) {
  if (!is.character(range_or_sheet) || length(range_or_sheet) != 1L ||
      is.na(range_or_sheet) || !nzchar(range_or_sheet))
    stop("[gs_clear_values] `range_or_sheet` must be one string: a tab name or 'Tab'!A1:F20",
         call. = FALSE)
  rng <- if (grepl("!", range_or_sheet, fixed = TRUE)) range_or_sheet else
    sprintf("'%s'", gsub("'", "''", range_or_sheet, fixed = TRUE))
  resp <- googlesheets4::request_make(googlesheets4::request_generate(
    "sheets.spreadsheets.values.clear",
    params = list(spreadsheetId = as.character(googlesheets4::as_sheets_id(ss)),
                  range = utils::URLencode(rng, reserved = TRUE))))
  if (httr::status_code(resp) >= 400L)
    stop("[gs_clear_values] HTTP ", httr::status_code(resp), " for '", rng, "': ",
         substr(httr::content(resp, as = "text", encoding = "UTF-8"), 1L, 300L), call. = FALSE)
  done <- httr::content(resp, as = "parsed")$clearedRange
  message(sprintf("[gs_clear_values] cleared values in %s", done))
  invisible(done)
}

# ── Conditional-format management (idempotent re-runs) ---------------------

#' Count existing conditional-format rules on a sheet. Always check before
#' deleting — `deleteConditionalFormatRule` errors HTTP 400 on a missing
#' index and takes down the entire atomic batch.
count_cond_rules <- function(ss_id, sheet_id) {
  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.get",
    params = list(spreadsheetId = ss_id,
                  fields = "sheets(properties(sheetId),conditionalFormats)")
  )
  body <- httr::content(googlesheets4::request_make(req), as = "parsed")
  for (s in body$sheets) {
    if (isTRUE(s$properties$sheetId == sheet_id)) {
      return(length(s$conditionalFormats %||% list()))
    }
  }
  0L
}

#' Build delete requests for ALL existing cond-format rules on a sheet.
#' Combine with `c()` before adding fresh rules.
fmt_delete_cond_rules <- function(ss_id, sheet_id) {
  n <- count_cond_rules(ss_id, sheet_id)
  if (n == 0L) return(list())
  # Descending — each delete shifts later indices by -1.
  lapply(seq.int(n, 1L), function(i)
    list(deleteConditionalFormatRule = list(sheetId = sheet_id, index = i - 1L)))
}

# ── Reference-tab dump (the visual contract) --------------------------------

#' Dump a tab's full visual contract — values + formulas + effectiveFormat +
#' merges + hidden rows + col widths + conditional formats — to a text file.
#'
#' Use BEFORE writing R code to regenerate a reference tab. Re-run AFTER your
#' build and diff against the reference to catch every miss.
#'
#' @param ss_id     spreadsheet ID (string)
#' @param tab_title name of the tab to dump
#' @param range     A1 range, e.g. "A1:AF500"
#' @param out_path  path to write the text dump
dump_reference_tab <- function(ss_id, tab_title, range, out_path) {
  fields <- paste0(
    "sheets(",
      "properties(title,gridProperties(frozenRowCount,frozenColumnCount,hideGridlines)),",
      "merges,",
      "conditionalFormats,",
      "data(",
        "rowMetadata(hiddenByUser),",
        "columnMetadata(pixelSize,hiddenByUser),",
        "rowData(values(",
          "formattedValue,userEnteredValue,",
          "effectiveFormat(",
            "backgroundColor,horizontalAlignment,verticalAlignment,",
            "numberFormat(type,pattern),",
            "textFormat(foregroundColor,bold,italic,fontSize,fontFamily),",
            "borders(top,bottom,left,right)",
          ")",
        "))",
      ")",
    ")"
  )
  rng <- sprintf("'%s'!%s", tab_title, range)
  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.get",
    params = list(spreadsheetId = ss_id, ranges = rng, fields = fields)
  )
  body <- httr::content(googlesheets4::request_make(req), as = "parsed")
  con <- file(out_path, "w"); on.exit(close(con), add = TRUE)

  hex <- function(c) {
    if (is.null(c)) return("")
    r <- ifelse(is.null(c$red),   0, c$red)
    g <- ifelse(is.null(c$green), 0, c$green)
    b <- ifelse(is.null(c$blue),  0, c$blue)
    sprintf("#%02X%02X%02X", round(r * 255), round(g * 255), round(b * 255))
  }
  bd <- function(b) {
    if (is.null(b) || is.null(b$style) || b$style == "NONE") return("")
    sprintf("%s/%s", b$style, hex(b$colorStyle$rgbColor))
  }

  for (sh in body$sheets) {
    if (sh$properties$title != tab_title) next
    gp <- sh$properties$gridProperties
    cat(sprintf("# tab=%s frozenRows=%s frozenCols=%s hideGridlines=%s\n",
                tab_title,
                ifelse(is.null(gp$frozenRowCount),    0, gp$frozenRowCount),
                ifelse(is.null(gp$frozenColumnCount), 0, gp$frozenColumnCount),
                ifelse(is.null(gp$hideGridlines), FALSE, gp$hideGridlines)),
        file = con)
    for (m in sh$merges %||% list()) {
      cat(sprintf("MERGE rows %d..%d cols %d..%d\n",
                  m$startRowIndex, m$endRowIndex,
                  m$startColumnIndex, m$endColumnIndex), file = con)
    }
    for (cf in sh$conditionalFormats %||% list()) {
      for (r in cf$ranges) {
        kind <- if (!is.null(cf$gradientRule)) "GRADIENT" else "BOOLEAN"
        cat(sprintf("CF %s rows %s..%s cols %s..%s\n", kind,
                    r$startRowIndex, r$endRowIndex,
                    r$startColumnIndex, r$endColumnIndex), file = con)
      }
    }
    if (length(sh$data) == 0L) next
    d <- sh$data[[1L]]
    sr <- ifelse(is.null(d$startRow),    0, d$startRow)
    sc <- ifelse(is.null(d$startColumn), 0, d$startColumn)

    if (!is.null(d$rowMetadata)) {
      for (i in seq_along(d$rowMetadata)) {
        if (isTRUE(d$rowMetadata[[i]]$hiddenByUser))
          cat(sprintf("HIDDEN_ROW %d\n", sr + i), file = con)
      }
    }
    if (!is.null(d$columnMetadata)) {
      for (j in seq_along(d$columnMetadata)) {
        cm <- d$columnMetadata[[j]]
        px <- cm$pixelSize
        hide <- isTRUE(cm$hiddenByUser)
        if (!is.null(px) || hide)
          cat(sprintf("COL %d width=%s hidden=%s\n", sc + j,
                      ifelse(is.null(px),"-",px), hide), file = con)
      }
    }

    if (is.null(d$rowData)) next
    for (i in seq_along(d$rowData)) {
      vals <- d$rowData[[i]]$values
      if (is.null(vals)) next
      for (j in seq_along(vals)) {
        cell <- vals[[j]]
        ef <- cell$effectiveFormat; uev <- cell$userEnteredValue
        fv <- cell$formattedValue
        val <- if (!is.null(uev$formulaValue)) sprintf("=%s", uev$formulaValue)
               else if (!is.null(uev$numberValue)) as.character(uev$numberValue)
               else if (!is.null(uev$stringValue)) sprintf("\"%s\"", uev$stringValue)
               else if (!is.null(fv)) fv else ""
        fmt <- ""
        if (!is.null(ef)) {
          tt <- ef$textFormat; bdr <- ef$borders
          fmt <- sprintf("bg=%s fg=%s %s%s fs=%s ha=%s nf=%s/%s bd[T=%s|B=%s|L=%s|R=%s]",
                         hex(ef$backgroundColor), hex(tt$foregroundColor),
                         ifelse(isTRUE(tt$bold), "B", "-"),
                         ifelse(isTRUE(tt$italic), "I", "-"),
                         ifelse(is.null(tt$fontSize), "", tt$fontSize),
                         ifelse(is.null(ef$horizontalAlignment), "", ef$horizontalAlignment),
                         ifelse(is.null(ef$numberFormat$type), "", ef$numberFormat$type),
                         ifelse(is.null(ef$numberFormat$pattern), "", ef$numberFormat$pattern),
                         bd(bdr$top), bd(bdr$bottom), bd(bdr$left), bd(bdr$right))
        }
        if (val != "" || (fmt != "" && grepl("(SOLID|DASHED|#[1-9A-F]|B-|-I|fs=[0-9])", fmt)))
          cat(sprintf("R%d C%d | %s | %s\n", sr + i, sc + j, val, fmt), file = con)
      }
    }
  }
  message(sprintf("[dump_reference_tab] wrote %s", out_path))
  invisible(out_path)
}
