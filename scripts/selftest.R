#!/usr/bin/env Rscript
# =============================================================================
# selftest.R — live self-test of the skill's helpers against Google Sheets
# =============================================================================
#
# Repo dev tool (NOT shipped in skills/). It builds things with the helpers on ONE
# scratch sheet, reads the result back from Google and prints a PASS/FAIL table.
# Run it after every change to a helper in skills/r-googlesheets4/scripts/:
#
#   Rscript scripts/selftest.R
#
# Needs the login saved by `bash skills/r-googlesheets4/scripts/gs_setup.sh auth <email>`. It uses the
# default `sheets` access level only, never shares anything, never raises the
# level. Exit status is non-zero when any check FAILs.
#
# Environment (all optional):
#   SELFTEST_SHEET_ID  reuse this scratch sheet. Without it a new one is created
#                      ('r-googlesheets4 selftest (safe to delete)') and its id is
#                      printed: pass it back next time so Drive does not fill up
#                      with copies. The script wipes tabs of that sheet, so it
#                      refuses any sheet whose title is not the scratch title.
#   GS_SKILL_DIR       skill folder to test (default skills/r-googlesheets4)
#   SELFTEST_ONLY      comma list of areas to run, e.g. "charts,rules"
#
# Runs for a few minutes: Google allows ~60 writes and ~60 reads a minute per user
# and request_make() waits out a 429, so expect one or two waits of about a minute.
#
# Each area is one function below. A check reads state BACK from Google (never trusts
# a helper's own "applied" message) and a few "fact:" checks pin down Google behaviour
# the docs rely on: if one of those FAILs, Google changed and the docs need updating.
# A SKIP is never a failure; it marks a known open problem and turns into a check once
# the problem is fixed. Adding a helper? Add its check to the area it belongs to
# (CONTRIBUTING.md): build with it, read the result back, assert on what Google stored.
# =============================================================================

# ── Setup ---------------------------------------------------------------------

args <- grep("^--file=", commandArgs(FALSE), value = TRUE)
ROOT  <- if (length(args)) normalizePath(file.path(dirname(sub("^--file=", "", args[1L])), "..")) else getwd()
SKILL <- normalizePath(Sys.getenv("GS_SKILL_DIR", file.path(ROOT, "skills", "r-googlesheets4")), mustWork = FALSE)
if (!file.exists(file.path(SKILL, "scripts", "gs_helpers.R")))
  stop("selftest: no skill found at '", SKILL, "'. Run from the repo root, or set GS_SKILL_DIR to the ",
       "skill folder (the one that holds scripts/gs_helpers.R).", call. = FALSE)
Sys.setenv(GS_SKILL_DIR = SKILL)
Sys.unsetenv("SHEET_ID")        # a SHEET_ID left in the shell must never steer a test at a real file
Sys.setenv(GS_SCOPE_LEVEL = "sheets")   # the least-privilege default; the test never asks for more

for (f in c("gs_helpers.R", "gs_buffer.R", "gs_qa.R", "gs_formulas.R", "gs_charts.R",
            "gs_modern.R", "brand.R", "gs_visual_qa.R"))
  suppressMessages(source(file.path(SKILL, "scripts", f)))

TITLE <- "r-googlesheets4 selftest (safe to delete)"
TABS  <- c("Cells", "Writes", "Q1", "R&D's", "Data", "Dash", "Rules", "Modern",
           "Formulas", "Wipe", "Keep", "Summary")

# ── Check helpers -------------------------------------------------------------

RESULTS <- list()
AREA    <- ""

record <- function(status, label, detail = NULL) {
  RESULTS[[length(RESULTS) + 1L]] <<- list(area = AREA, status = status, label = label)
  cat(sprintf("%-4s  %-8s  %s\n", status, AREA, label))
  if (!is.null(detail) && nzchar(detail))
    cat("          ", substr(gsub("\n", " ", detail), 1L, 400L), "\n", sep = "")
}

#' One check. `cond` is evaluated here, so an error inside it is a FAIL, not a crash.
#' `got` (optional) is shown only when the check fails.
check <- function(label, cond, got = NULL) {
  err <- NULL
  ok <- tryCatch(isTRUE(cond), error = function(e) { err <<- paste("error:", conditionMessage(e)); FALSE })
  if (ok) return(record("PASS", label))
  if (is.null(err) && !missing(got))
    err <- tryCatch(paste("got:", paste(format(got), collapse = " | ")), error = function(e) NULL)
  record("FAIL", label, err)
}

skip <- function(label, why) record("SKIP", label, why)

# Error message of `expr`, or NA when it ran fine.
errs <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
has_err <- function(e, text) !is.na(e) && grepl(text, e, fixed = TRUE)

# Value and warning messages of `expr`.
with_warns <- function(expr) {
  w <- character()
  v <- withCallingHandlers(expr, warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
  list(value = v, warnings = w)
}

# Re-run `fn` until `done(value)` holds (Sheets needs a moment to render pivots, hidden columns).
poll <- function(fn, done, tries = 5L, wait = 2) {
  for (i in seq_len(tries)) {
    v <- fn()
    if (isTRUE(done(v))) return(v)
    if (i < tries) Sys.sleep(wait)
  }
  v
}

# pdftoppm (called by pdf_to_pngs) prints poppler warnings about Google's PDFs; hide them.
no_poppler_noise <- function(expr) {
  assign("system2", function(command, args = character(), ...) base::system2(command, args, ..., stderr = FALSE), envir = globalenv())
  on.exit(rm("system2", envir = globalenv()))
  expr
}

# Helpers talk through message(); keep the table readable but let rate-limit waits show.
quiet <- function(expr) withCallingHandlers(expr, message = function(m)
  if (!grepl("Request failed|429|Retry", conditionMessage(m))) invokeRestart("muffleMessage"))

# ── Reading the sheet back -----------------------------------------------------

IDS <- NULL
refresh_ids <- function() {
  p <- googlesheets4::sheet_properties(ss)
  IDS <<- stats::setNames(p$id, p$name)
  invisible(IDS)
}
sid <- function(tab) IDS[[tab]]

# One spreadsheets.get. With `ranges` the grid data of that range comes with it.
api_get <- function(fields, ranges = NULL) {
  p <- list(spreadsheetId = SSID, fields = fields)
  if (!is.null(ranges)) { p$ranges <- ranges; p$includeGridData <- TRUE }
  resp <- request_make(request_generate("sheets.spreadsheets.get", params = p))
  if (httr::status_code(resp) >= 400L)
    stop("spreadsheets.get HTTP ", httr::status_code(resp), ": ", substr(httr::content(resp, as = "text", encoding = "UTF-8"), 1L, 300L))
  httr::content(resp, as = "parsed")
}
tab_of <- function(body, tab) Find(function(s) identical(s$properties$title, tab), body$sheets)

CELL_ALL <- "formattedValue,effectiveValue,userEnteredValue,userEnteredFormat,effectiveFormat,dataValidation,note,pivotTable"
# Rows of cells for `a1` (a range starting at A1): a list of rows, each with $values.
grid <- function(tab, a1, cell_fields = CELL_ALL) {
  b <- api_get(sprintf("sheets(data(rowData(values(%s))))", cell_fields),
               ranges = sprintf("'%s'!%s", gsub("'", "''", tab, fixed = TRUE), a1))
  b$sheets[[1L]]$data[[1L]]$rowData %||% list()
}
# Cell (r, c), 1-based, as a list; an unset cell is list().
cell_at <- function(rows, r, c) if (r <= length(rows) && c <= length(rows[[r]]$values %||% list())) rows[[r]]$values[[c]] else list()
hex <- function(col) if (is.null(col)) NA_character_ else color_to_hex(col)   # the API sends black as {}
text_fmt <- function(cell) cell$userEnteredFormat$textFormat %||% list()
# Numbers parse from JSON as integer or double; compare by value.
eq <- function(a, b) length(a) == 1L && length(b) == 1L && !is.na(a) && isTRUE(all.equal(as.numeric(a), as.numeric(b)))

# ── Applying requests ---------------------------------------------------------

apply_ok <- function(label, reqs) {
  e <- errs(batch_format(ss, reqs, strict = TRUE))
  check(label, is.na(e), got = e)
  is.na(e)
}
flush_ok <- function(label) {
  r <- NULL
  e <- errs(r <- flush_writes(ss, strict = TRUE))
  check(label, is.na(e) && !is.null(r) && httr::status_code(r) == 200L && length(.wb$data) == 0L, got = e)
}
hide_col <- function(tab, col0, hidden = TRUE)
  batch_format(ss, list(list(updateDimensionProperties = list(
    range = list(sheetId = sid(tab), dimension = "COLUMNS", startIndex = col0, endIndex = col0 + 1L),
    properties = list(hiddenByUser = hidden), fields = "hiddenByUser"))), strict = TRUE)

# ── Area: offline (no API) ----------------------------------------------------

area_offline <- function() {
  check("hex_to_color / color_to_hex round-trip every level of every channel",
        all(vapply(0:255, function(i) { h <- sprintf("#%02X%02X%02X", i, 255L - i, (i * 7L) %% 256L)
                                        identical(color_to_hex(hex_to_color(h)), h) }, NA)))
  check("color_to_hex: a channel the API left out counts as 0", identical(color_to_hex(list(red = 1)), "#FF0000"))
  check("color_to_hex: rejects a non-list", !is.na(errs(color_to_hex("#fff"))))
  check("col_letter and grid_range", col_letter(27L) == "AA" && col_letter(702L) == "ZZ" &&
          identical(unlist(grid_range(7, 2, 3, 1, 4)),
                    c(sheetId = 7, startRowIndex = 1, endRowIndex = 3, startColumnIndex = 0, endColumnIndex = 4)))
  check("f_sumifs, named list and pair list", identical(f_sumifs("P!C:C", list("P!A:A" = "Tech")), '=SUMIFS(P!C:C,P!A:A,"Tech")') &&
          identical(f_sumifs("P!C:C", list(c("P!A:A", "x"), c("P!B:B", "y"))), '=SUMIFS(P!C:C,P!A:A,"x",P!B:B,"y")'))
  check("f_safe_div, f_iferror, f_named, f_query, fraw",
        identical(f_safe_div("B2", "C2"), '=IF(C2=0,"",B2/C2)') && identical(f_iferror("=A1/B1"), '=IFERROR(A1/B1,"")') &&
          identical(f_named("={a}*{b}", a = "B5", b = "arpu"), "=B5*arpu") && identical(fraw("=SUM(A1)"), "SUM(A1)") &&
          identical(f_query("D!A:M", "select A where B = 'x'", 1L), "=QUERY(D!A:M,\"select A where B = 'x'\",1)"))
  check("f_sparkline: numbers bare, strings quoted, I() verbatim, NULL option dropped",
        identical(f_sparkline("B2:M2", list(charttype = "line", linewidth = 2, color = "#2457C5")),
                  '=SPARKLINE(B2:M2, {"charttype","line";"linewidth",2;"color","#2457C5"})') &&
          identical(f_sparkline("H2", list(max = I("$H$1"))), '=SPARKLINE(H2, {"max",$H$1})') &&
          identical(f_sparkline("A1", list(max = NULL)), "=SPARKLINE(A1)") && !is.na(errs(f_sparkline("A1", list(1, 2)))))
  check("f_sparkline(iferror = TRUE) wraps in IFERROR and composes with color_to_hex",
        identical(f_sparkline("B2:M2", list(color = color_to_hex(hex_to_color("2457C5"))), iferror = TRUE),
                  '=IFERROR(SPARKLINE(B2:M2, {"color","#2457C5"}),"")'))
  check("parse_hyperlink, parse_num, safe_locale_date",
        identical(parse_hyperlink('=HYPERLINK("https://x.test","a ""b""")'), list(url = "https://x.test", label = 'a "b"')) &&
          is.null(parse_hyperlink("plain")) && identical(parse_num(c("$1,234.56", "-$100", "12.5%")), c(1234.56, -100, 12.5)) &&
          identical(safe_locale_date(as.Date("2026-03-14")), "March 14, 2026"))
  check("fmt_cells: numfmt together with numfmt_type stops; numfmt must be list(type =)",
        !is.na(errs(fmt_cells(1, 1, 1, 1, 1, numfmt = NUMFMT_INT, numfmt_type = "NUMBER"))) &&
          !is.na(errs(fmt_cells(1, 1, 1, 1, 1, numfmt = "0.0")))
        && identical(fmt_cells(1, 1, 1, 1, 1, numfmt = NUMFMT_PCT), fmt_cells(1, 1, 1, 1, 1, numfmt_type = "PERCENT", numfmt_pattern = "0.0%")))
  check("fmt_named_range rejects an invalid name", !is.na(errs(fmt_named_range(1, "1bad name", 1, 1, 1, 1))))
  check("fmt_protected_range: partial bounds and unprotected_ranges on a bounded range stop",
        !is.na(errs(fmt_protected_range(1, 1L, 2L, 1L))) &&
          !is.na(errs(fmt_protected_range(1, 1, 2, 1, 2, unprotected_ranges = list(grid_range(1, 1, 1, 1, 1))))))
  check("fmt_validation: bad type, wrong value count, NA, formula without '='",
        has_err(errs(fmt_validation(1, 1, 1, 1, 1, "NOPE")), "must be one of") &&
          has_err(errs(fmt_validation(1, 1, 1, 1, 1, "NUMBER_BETWEEN", 1)), "takes 2") &&
          has_err(errs(fmt_validation(1, 1, 1, 1, 1, "NUMBER_EQ", NA_real_)), "NA") &&
          has_err(errs(fmt_validation(1, 1, 1, 1, 1, "CUSTOM_FORMULA", "A1>0")), "starts with '='"))
  check("fmt_validation: named values still serialise as a JSON array",
        identical(names(fmt_validation(1, 1, 1, 1, 1, "NUMBER_BETWEEN", c(lo = 0, hi = 1))$setDataValidation$rule$condition$values), NULL))
  check("fmt_cond_formula / fmt_cond_text / rules without a format stop",
        !is.na(errs(fmt_cond_formula(1, 1, 1, 1, 1, "A1>0", bg_color = COL_RED_LIGHT))) &&
          !is.na(errs(fmt_cond_text(1, 1, 1, 1, 1, op = "contains", bg_color = COL_RED_LIGHT))) &&
          !is.na(errs(fmt_cond_number(1, 1, 1, 1, 1, 5))))
  check("fmt_cond_text_equals is fmt_cond_text(op = 'equals')",
        identical(fmt_cond_text_equals(1, 1, 5, 1, 1, "x", bg_color = COL_RED_LIGHT, index = 2L),
                  fmt_cond_text(1, 1, 5, 1, 1, op = "equals", text = "x", bg_color = COL_RED_LIGHT, index = 2L)))
  check("fmt_theme_colors: bad hex stops; a hex_to_color() list passes",
        !is.na(errs(fmt_theme_colors(accent1 = "blue"))) && is.na(errs(fmt_theme_colors(accent1 = hex_to_color("2457C5")))))
  check("fmt_tab_order: empty or repeated tabs stop before any call",
        !is.na(errs(fmt_tab_order(NULL, numeric()))) && !is.na(errs(fmt_tab_order(NULL, c(1, 1)))))
  check("gs_reset_tabs without tabs stops before any call",
        has_err(errs(gs_reset_tabs("not-an-id")), "`tabs` is required"))
  check("gs_open_or_create: an unnamed rows/cols vector longer than 1 stops before creating anything",
        has_err(errs(gs_open_or_create("x", "t", id = "", rows = c(1, 2))), "named by tab"))
  check("gs_clear_values: bad input stops before any call",
        all(vapply(list(NULL, c("a", "b"), "", NA_character_, 3), function(b)
          has_err(errs(gs_clear_values("not-an-id", b)), "must be one string"), NA)))
}

# ── Area: auth (account resolution, token inventory, gs_connect refusals) ------------

area_auth <- function() {
  vars <- c("GS_CONFIG", "GS_EMAIL", "GS_OAUTH_CACHE", "GS_SA_JSON")
  keep <- Sys.getenv(vars, unset = NA)
  on.exit(for (k in vars) if (is.na(keep[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(keep[[k]]), k)), add = TRUE)
  cfg <- tempfile("gs-config-")
  Sys.setenv(GS_CONFIG = cfg); Sys.unsetenv("GS_EMAIL")          # a temp config: the real saved account is never touched
  check("gs_config_path honours GS_CONFIG; with no file there is no saved account", identical(gs_config_path(), path.expand(cfg)) && is.null(gs_config_email()))
  gs_save_config_email("  Me@Example.COM ")
  check("gs_save_config_email stores it lower-cased and gs_config_email reads it back", identical(gs_config_email(), "me@example.com"))
  Sys.setenv(GS_EMAIL = "Env@Example.com")
  check("gs_resolve_email: argument, then GS_EMAIL, then the config file (always lower-case)",
        identical(gs_resolve_email("Arg@Example.com"), "arg@example.com") && identical(gs_resolve_email(), "env@example.com") &&
          identical({ Sys.unsetenv("GS_EMAIL"); gs_resolve_email(NA_character_) }, "me@example.com"))
  unlink(cfg)

  cache <- tempfile("gs-cache-"); dir.create(cache)
  Sys.setenv(GS_OAUTH_CACHE = cache)
  empty <- gs_cached_logins()
  writeLines("not a token", file.path(cache, "x_broken@example.invalid"))
  bad <- gs_cached_logins()
  check("gs_oauth_cache honours GS_OAUTH_CACHE; gs_cached_logins: empty cache, and a corrupt file is reported, not fatal",
        identical(gs_oauth_cache(), path.expand(cache)) && nrow(empty) == 0L && identical(names(empty), c("email", "scopes", "has_scope", "file")) &&
          nrow(bad) == 0L && length(attr(bad, "unreadable")) == 1L)
  e <- errs(gs_connect("nobody@example.invalid"))
  check("gs_connect: an account with no saved login stops with the fix command and opens no browser",
        has_err(e, "No saved Google login"), got = e)
  Sys.setenv(GS_SA_JSON = file.path(cache, "no-such-key.json"))
  check("gs_connect: a GS_SA_JSON that does not exist stops before anything else", has_err(errs(gs_connect()), "does not exist"))
  unlink(cache, recursive = TRUE)
  for (k in vars) if (is.na(keep[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(keep[[k]]), k))

  if (is.na(keep[["GS_SA_JSON"]])) {
    lg <- gs_cached_logins()
    check("gs_cached_logins / gs_has_login: the saved login of the connected account has exactly the sheets scope",
          nrow(lg) >= 1L && gs_has_login(lg, ACCT) && !gs_has_login(lg, "nobody@example.invalid"))
  } else skip("gs_cached_logins / gs_has_login", "running with a service account (GS_SA_JSON), so there is no saved user login")
  live <- gs_live_check(googlesheets4::gs4_token())
  check("gs_live_check: the token works against the Sheets API", isTRUE(live$ok), got = live$message)
  check("gs_require_level: passes at the current level, stops with the fix otherwise",
        isTRUE(gs_require_level("x", levels = GS_SCOPE_LEVEL)) && has_err(errs(gs_require_level("sharing", levels = "no-such-level")), "needs Drive access"))
}

# ── Area: cells (fmt_cells layering, sheet properties, merges, ...) ---------------

area_cells <- function() {
  t <- "Cells"
  gs_reset_tabs(ss, t)
  s <- sid(t); BLUE <- hex_to_color("2457C5")

  write_block(ss, t, 1, 1, rbind(c("Header", "B", "C", "D")))
  write_cell(ss, t, 2, 1, "bold then reset")
  write_cell(ss, t, 3, 1, "a much longer label that forces the column wider than its default width")
  write_block(ss, t, 1, 5, matrix(c(1234.5, 0.256, 2.5, 45000), ncol = 1))      # E1:E4
  write_cell(ss, t, 10, 7, "foo and foo")                                         # G10
  hdr <- write_section_header(ss, t, s, 8, "SECTION", start_col = 8, end_col = 10, bg_color = COL_BRAND)
  hdr_alt <- write_section_header_brand(ss, t, s, 9, "ALT", start_col = 8, end_col = 10, alt = TRUE)
  flush_writes(ss, strict = TRUE)

  # Layering: later calls that name only some properties keep the rest. The list is NAMED on purpose.
  lay <- list(
    fmt_cells(s, 1, 1, 1, 4, font_family = "Arial", font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = BLUE),
    fmt_cells(s, 2, 2, 1, 1, bold = TRUE),
    fmt_cells(s, 1, 1, 1, 4, font_size = 14),
    fmt_cells(s, 2, 2, 1, 1, bold = FALSE))
  names(lay) <- paste0("r", seq_along(lay))
  apply_ok("batch_format: a NAMED request list is sent as an array", lay)
  apply_ok("fmt_cells: numfmt constants, a custom list and the old type/pattern pair", list(
    fmt_cells(s, 1, 1, 5, 5, numfmt = NUMFMT_CURRENCY),
    fmt_cells(s, 2, 2, 5, 5, numfmt = NUMFMT_PCT, bold = TRUE),
    fmt_cells(s, 3, 3, 5, 5, numfmt = list(type = "NUMBER", pattern = '0.0"x"')),
    fmt_cells(s, 4, 4, 5, 5, numfmt_type = "NUMBER", numfmt_pattern = '$#,##0.0,"K"')))
  apply_ok("apply_style keeps the preset when only font_size / italic are overridden",
           c(hdr, hdr_alt, list(apply_style(s, 8, 8, 8, 10, list(), font_size = 16, italic = TRUE))))
  apply_ok("link_cells_req, then fmt_cells(bold) after it", list(
    link_cells_req(s, 6, 1, "Docs", "https://example.com/x"),
    fmt_cells(s, 6, 6, 1, 1, bold = TRUE, font_size = 12)))
  apply_ok("sheet properties, borders, groups, banding, named range, find/replace, image, auto-resize", c(
    list(fmt_freeze(s, rows = 1L), fmt_gridlines(s, show = FALSE), fmt_tab_color(s, BLUE),
         fmt_col_width(s, 6, 6, 150), fmt_row_height(s, 1, 1, 40),
         fmt_borders(s, 12, 13, 1, 3, top = list(style = "SOLID"), bottom = list(style = "DOUBLE", color = BLUE),
                     inner_h = list(style = "DOTTED")),
         fmt_unmerge(s, 15, 15, 1, 3), fmt_merge(s, 15, 15, 1, 3),       # unmerge first = safe to re-run
         fmt_banding(s, 25, 30, 1, 3, header_color = BLUE),
         fmt_named_range(s, "ST_CELLS", 2, 4, 5, 5),
         fmt_find_replace("foo", "bar", sheet_id = s),
         fmt_image_cell(s, 1, 11, "https://example.com/logo.png")),
    fmt_group_rows(s, 20, 22, collapsed = TRUE), fmt_group_cols(s, 13, 14, collapsed = FALSE),
    list(fmt_auto_resize_cols(s, 1, 4), fmt_auto_resize_rows(s, 2, 3))))

  b <- api_get(paste0("namedRanges(name),sheets(properties(title,tabColorStyle,gridProperties(frozenRowCount,hideGridlines)),",
                      "merges,bandedRanges(bandedRangeId),rowGroups,columnGroups,data(rowMetadata(pixelSize,hiddenByUser),",
                      "columnMetadata(pixelSize),rowData(values(", CELL_ALL, "))))"), ranges = "Cells!A1:N30")
  sh <- tab_of(b, t); d <- sh$data[[1L]]; rows <- d$rowData
  tf <- function(r, c) text_fmt(cell_at(rows, r, c))
  check("fmt_cells layering: a font_size-only call keeps bold, family, white text and the blue fill",
        isTRUE(tf(1, 1)$bold) && tf(1, 1)$fontSize == 14 && identical(tf(1, 1)$fontFamily, "Arial") &&
          identical(hex(tf(1, 1)$foregroundColorStyle$rgbColor), "#FFFFFF") &&
          identical(hex(cell_at(rows, 1, 1)$userEnteredFormat$backgroundColor), "#2457C5"))
  check("fmt_cells: an explicit bold = FALSE resets bold", !isTRUE(tf(2, 1)$bold))
  nf <- vapply(1:4, function(r) cell_at(rows, r, 5)$formattedValue %||% "", "")
  check("fmt_cells numfmt: $1,235 | 25.6% | 2.5x | $45.0K", identical(nf, c("$1,235", "25.6%", "2.5x", "$45.0K")), got = nf)
  check("fmt_cells numfmt = NUMFMT_PCT with bold keeps both", isTRUE(tf(2, 5)$bold))
  check("apply_style layering: bold + white kept, size 16 + italic applied, brand fill",
        isTRUE(tf(8, 8)$bold) && tf(8, 8)$fontSize == 16 && isTRUE(tf(8, 8)$italic) &&
          identical(hex(tf(8, 8)$foregroundColorStyle$rgbColor), "#FFFFFF") &&
          identical(hex(cell_at(rows, 8, 8)$userEnteredFormat$backgroundColor), "#2457C5"))
  check("write_section_header: merge H8:J8 and a 30px row",
        any(vapply(sh$merges, function(m) identical(c(m$startRowIndex, m$endRowIndex, m$startColumnIndex, m$endColumnIndex), c(7L, 8L, 7L, 10L)), NA)) &&
          d$rowMetadata[[8]]$pixelSize == 30)
  check("write_section_header_brand(alt = TRUE): the deep brand fill, white bold label, merged",
        identical(hex(cell_at(rows, 9, 8)$userEnteredFormat$backgroundColor), color_to_hex(COL_BRAND_DEEP)) &&
          isTRUE(tf(9, 8)$bold) && identical(cell_at(rows, 9, 8)$formattedValue, "ALT") && length(sh$merges) == 3L)
  check("link_cells_req: the link survives fmt_cells(bold, size)",
        identical(tf(6, 1)$link$uri, "https://example.com/x") && isTRUE(tf(6, 1)$bold) && tf(6, 1)$fontSize == 12)
  check("fmt_freeze rows, fmt_gridlines off, fmt_tab_color",
        sh$properties$gridProperties$frozenRowCount == 1 && isTRUE(sh$properties$gridProperties$hideGridlines) &&
          identical(hex(sh$properties$tabColorStyle$rgbColor), "#2457C5"))
  check("fmt_col_width / fmt_row_height", d$columnMetadata[[6]]$pixelSize == 150 && d$rowMetadata[[1]]$pixelSize == 40)
  check("fmt_auto_resize_cols widened column A to its long label", d$columnMetadata[[1]]$pixelSize > 150, got = d$columnMetadata[[1]]$pixelSize)
  check("fmt_borders: top SOLID on row 12, bottom DOUBLE on row 13",
        identical(cell_at(rows, 12, 1)$userEnteredFormat$borders$top$style, "SOLID") &&
          identical(cell_at(rows, 13, 1)$userEnteredFormat$borders$bottom$style, "DOUBLE"))
  check("fmt_unmerge + fmt_merge in one batch leave exactly the three merges (2 section headers + A15:C15)", length(sh$merges) == 3L, got = length(sh$merges))
  check("fmt_group_rows(collapsed = TRUE) hides rows 20-22; fmt_group_cols(collapsed = FALSE) leaves 13-14 visible",
        length(sh$rowGroups) == 1L && all(vapply(20:22, function(r) isTRUE(d$rowMetadata[[r]]$hiddenByUser), NA)) &&
          length(sh$columnGroups) == 1L && !any(vapply(13:14, function(c) isTRUE(d$columnMetadata[[c]]$hiddenByUser), NA)))
  check("fmt_banding", length(sh$bandedRanges) == 1L)
  check("fmt_named_range", identical(vapply(b$namedRanges, function(n) n$name, ""), "ST_CELLS"))
  check("fmt_find_replace: foo -> bar", identical(cell_at(rows, 10, 7)$formattedValue, "bar and bar"))
  check("fmt_image_cell IN_CELL writes an =IMAGE() formula", grepl("IMAGE(", cell_at(rows, 1, 11)$userEnteredValue$formulaValue %||% "", fixed = TRUE))
  check("color_to_hex reads a colour back from the sheet (tab colour round trip)",
        identical(color_to_hex(sh$properties$tabColorStyle$rgbColor), "#2457C5"))
  check("get_sheet_id: finds a tab, stops on an unknown one",
        get_sheet_id(ss, t) == s && has_err(errs(get_sheet_id(ss, "NoSuchTab")), "No sheet named"))
}

# ── Area: writes (write_cell / write_block / flush_writes / read_values / gs_clear_values) ---

area_writes <- function() {
  t <- "Writes"
  gs_reset_tabs(ss, c(t, "Q1", "R&D's"))
  vals <- list(2e6, 0.0025, "-5", "+abc", "'abc", "@x", NA, TRUE, "=1+2", "plain")
  for (i in seq_along(vals)) write_cell(ss, t, i, 1, vals[[i]])
  write_cell(ss, t, 11, 1, "00123", as_text = TRUE)
  write_block(ss, t, 1, 3, data.frame(a = c("x", "-y"), b = c(1.5, 2e6)))                   # C1:D2
  write_cell(ss, t, 1, 5, 1); write_cell(ss, t, 1, 6, 2); write_cell(ss, t, 1, 7, 3); write_cell(ss, t, 2, 5, 4)   # ragged E1:G2
  write_block(ss, "R&D's", 1, 1, data.frame(k = c("a", "b"), v = c(1, 2)))
  check("11 write_cell + 4 write_cell + 2 write_block calls queue 17 entries (a block is ONE)", length(.wb$data) == 17L, got = length(.wb$data))
  flush_ok("flush_writes(strict = TRUE): HTTP 200 and the buffer is empty")

  rows <- grid(t, "A1:G11")
  ev <- function(r, c) cell_at(rows, r, c)$effectiveValue
  fv <- function(r, c) cell_at(rows, r, c)$formattedValue
  check("write_cell: 2e6 is the NUMBER 2000000, shown as 2000000 (not 2.00E+06)", eq(ev(1, 1)$numberValue, 2e6) && identical(fv(1, 1), "2000000"))
  check("write_cell: 0.0025 shows as 0.0025", identical(fv(2, 1), "0.0025"))
  check("write_cell: the string '-5' stays a number (-5)", eq(ev(3, 1)$numberValue, -5))
  check("write_cell: '+abc' and '@x' stay text", identical(ev(4, 1)$stringValue, "+abc") && identical(ev(6, 1)$stringValue, "@x"))
  check("write_cell: \"'abc\" keeps its apostrophe", identical(fv(5, 1), "'abc"))
  check("write_cell: NA is an empty cell, TRUE a boolean, '=1+2' a formula (3)",
        is.null(ev(7, 1)) && isTRUE(ev(8, 1)$boolValue) && eq(ev(9, 1)$numberValue, 3))
  check("write_cell(as_text = TRUE) keeps '00123' as text", identical(ev(11, 1)$stringValue, "00123"))
  check("write_block: '-y' stays text, 2e6 stays a number", identical(ev(2, 3)$stringValue, "-y") && eq(ev(2, 4)$numberValue, 2e6))

  write_cell(ss, t, 30, 1, "x"); clear_writes()
  check("clear_writes empties the buffer and flush_writes then returns NULL", length(.wb$data) == 0L && is.null(flush_writes(ss, strict = TRUE)))
  write_cell(ss, "NoSuchTab", 1, 1, "x")
  e <- errs(flush_writes(ss, strict = TRUE))
  check("flush_writes(strict = TRUE) stops on HTTP 400 and the spent buffer is cleared", has_err(e, "HTTP 400") && length(.wb$data) == 0L, got = e)
  write_cell(ss, "NoSuchTab", 1, 1, "x")
  r <- NULL
  e <- errs(r <- flush_writes(ss))
  check("flush_writes() default only logs a 400 (no error, the response says 400)", is.na(e) && httr::status_code(r) == 400L)

  ru <- read_values(ss, c(rag = "Writes!E1:G2", amp = "'R&D''s'!B1:B2", mix = "Writes!A1:A3"), "UNFORMATTED_VALUE")
  check("read_values: named result; all-number range is numeric; ragged rows pad with NA",
        identical(names(ru), c("rag", "amp", "mix")) && is.numeric(ru$rag) && identical(dim(ru$rag), c(2L, 3L)) &&
          is.na(ru$rag[2, 3]) && ru$rag[2, 1] == 4 && ru$rag[1, 3] == 3)
  check("read_values: a tab name with '&' and a quote works (URL-encoded); numeric column",
        identical(as.numeric(ru$amp), c(1, 2)) && identical(as.numeric(ru$mix), c(2e6, 0.0025, -5)))
  rf <- read_values(ss, c(fmt = "Writes!A1:A2", none = "Writes!P1:Q2"))
  check("read_values FORMATTED_VALUE is character; an empty range is a 0 x 0 matrix",
        is.character(rf$fmt) && identical(unname(rf$fmt[, 1]), c("2000000", "0.0025")) && identical(dim(rf$none), c(0L, 0L)))
  check("read_values(value_render = 'FORMULA') returns the formula", identical(read_values(ss, "Writes!A9", "FORMULA")[[1]][1, 1], "=1+2"))
  check("read_values: a failed range stops and names the range", has_err(errs(read_values(ss, "NoSuchTab!A1")), "NoSuchTab"))

  # gs_clear_values keeps formats, validation and notes; seeded in four places.
  reqs <- list()
  for (sd in list(list("Writes", 9L), list("Writes", 12L), list("Q1", 1L), list("R&D's", 4L))) {
    tab <- sd[[1]]; c0 <- sd[[2]]; sh <- sid(tab)
    write_block(ss, tab, 1, c0, data.frame(n = c(10, 20, 30, 40, 50), t = c("x", "y", "x", "y", "x")))
    reqs <- c(reqs, list(
      fmt_cells(sh, 1, 5, c0, c0, numfmt_type = "CURRENCY", numfmt_pattern = "$#,##0.00"),
      fmt_cells(sh, 1, 5, c0 + 1L, c0 + 1L, bg_color = hex_to_color("FFF2CC")),
      fmt_dropdown(sh, 1, 5, c0 + 1L, c0 + 1L, values = c("x", "y")),
      list(updateCells = list(rows = list(list(values = list(list(note = "keep me")))), fields = "note",
                              start = list(sheetId = sh, rowIndex = 0L, columnIndex = c0 - 1L)))))
  }
  flush_writes(ss, strict = TRUE)
  apply_ok("seed formats, validation and notes for the clear tests", reqs)

  gs_clear_values(ss, "Writes!I1:J5")
  g <- grid(t, "A1:M5")
  check("gs_clear_values(range): values gone", is.null(cell_at(g, 1, 9)$effectiveValue) && is.null(cell_at(g, 2, 10)$effectiveValue))
  check("gs_clear_values(range): number format, fill, validation and note are kept",
        identical(cell_at(g, 1, 9)$userEnteredFormat$numberFormat$type, "CURRENCY") &&
          !is.null(cell_at(g, 2, 10)$userEnteredFormat$backgroundColor) &&
          identical(cell_at(g, 2, 10)$dataValidation$condition$type, "ONE_OF_LIST") && identical(cell_at(g, 1, 9)$note, "keep me"))
  check("gs_clear_values(range): the neighbouring range keeps its values", eq(cell_at(g, 1, 12)$effectiveValue$numberValue, 10))
  suppressMessages(googlesheets4::range_clear(ss, sheet = t, range = "L1:M5"))
  g <- grid(t, "A1:M5")
  check("fact: googlesheets4::range_clear() default (reformat = TRUE) LOSES the number format", is.null(cell_at(g, 1, 12)$userEnteredFormat$numberFormat))

  gs_clear_values(ss, "Q1")                       # a tab named like a cell
  g <- grid("Q1", "A1:B5")
  check("gs_clear_values('Q1'): a tab named like a cell is cleared whole; format and validation stay",
        is.null(cell_at(g, 1, 1)$effectiveValue) && identical(cell_at(g, 1, 1)$userEnteredFormat$numberFormat$type, "CURRENCY") &&
          !is.null(cell_at(g, 2, 2)$dataValidation))
  gs_clear_values(ss, "R&D's")                    # '&' and an apostrophe in the name
  g <- grid("R&D's", "A1:E5")
  check("gs_clear_values(\"R&D's\"): '&' and a quote in the tab name; format stays",
        is.null(cell_at(g, 1, 1)$effectiveValue) && is.null(cell_at(g, 2, 2)$effectiveValue) &&
          identical(cell_at(g, 1, 4)$userEnteredFormat$numberFormat$type, "CURRENCY"))
  e <- errs(gs_clear_values(ss, "A1:B5"))
  check("gs_clear_values: a bare 'A1:B5' is refused (HTTP 400) and clears nothing",
        has_err(e, "HTTP 400") && identical(read_values(ss, "Writes!A1", "UNFORMATTED_VALUE")[[1]][1, 1], 2e6), got = e)
}

# ── Area: charts (every kind, cross-tab, style, view windows, audit) --------------

area_charts <- function() {
  gs_reset_tabs(ss, c("Data", "Dash"))
  sd <- sid("Data"); dash <- sid("Dash")
  BLUE <- hex_to_color("2457C5"); RED <- hex_to_color("C62828"); AMB <- hex_to_color("E0A100")
  write_block(ss, "Data", 1, 1, rbind(c("Month", "Revenue", "Costs", "Profit")))
  write_block(ss, "Data", 2, 1, data.frame(m = month.abb[1:6], r = c(120, 135, 150, 148, 165, 175),
                                           c = c(90, 95, 101, 104, 112, 118), p = c(30, 40, 49, 44, 53, 57)))
  write_block(ss, "Data", 1, 6, rbind(c("Step", "Value")))
  write_block(ss, "Data", 2, 6, data.frame(l = c("Opening", "Sales", "Refunds", "Costs", "Other", "Closing"),
                                           v = c(100, 60, -15, -40, -5, 100)))
  write_block(ss, "Data", 1, 9, rbind(c("Category", "Spend")))
  write_block(ss, "Data", 2, 9, data.frame(c = c("Rent", "Food", "Fun", "Travel", "Other"), s = c(1200, 600, 250, 300, 150)))
  write_block(ss, "Data", 1, 12, rbind("Hidden"))
  write_block(ss, "Data", 2, 12, data.frame(h = 1:6))
  flush_writes(ss, strict = TRUE)

  ser2 <- list(list(range = c(1, 7, 2, 2), color = BLUE), list(range = c(1, 7, 3, 3), color = RED))
  STYLE <- list(font = "Georgia", title_size = 16, title_bold = TRUE, title_color = "C62828", title_position = "CENTER",
                background = "FFF8E1", border = "2457C5", axis_font_size = 14)
  slot <- function(i) c(1L + 17L * ((i - 1L) %/% 3L), c(1L, 7L, 13L)[(i - 1L) %% 3L + 1L])   # i-th chart on Dash, 3 per row
  sz <- c(480L, 300L)
  y2 <- with_warns(fmt_chart_basic(sd, "C4 combo", "COMBO", c(1, 7, 1, 1),
          list(list(range = c(1, 7, 2, 2), color = BLUE, type = "COLUMN"),
               list(range = c(1, 7, 4, 4), color = AMB, type = "LINE", axis = "RIGHT_AXIS")),
          anchor = slot(3), size = sz, anchor_sheet_id = dash, y_title = "USD", y2_title = "Profit", y2_min = 0, y2_max = 100))
  check("y2_title / y2_min / y2_max warn that Sheets drops the right axis", any(grepl("RIGHT_AXIS", y2$warnings, fixed = TRUE)))
  charts <- list(
    fmt_chart_basic(sd, "C1 line same tab", "LINE", c(1, 7, 1, 1), ser2, anchor = c(10L, 1L), size = sz,
                    x_title = "Month", y_title = "USD", y_min = 80, y_max = 200),
    fmt_chart_basic(sd, "C2 stacked column", "COLUMN", c(1, 7, 1, 1), ser2, stacked_type = "STACKED",
                    anchor = slot(1), size = sz, anchor_sheet_id = dash),
    fmt_chart_basic(sd, "C3 area", "AREA", c(1, 7, 1, 1), ser2, anchor = slot(2), size = sz, anchor_sheet_id = dash),
    y2$value,
    fmt_chart_bar(sd, "C5 bar", c(1, 7, 1, 1), list(list(range = c(1, 7, 2, 2), color = BLUE)),
                  anchor = slot(4), size = sz, anchor_sheet_id = dash, x_title = "USD"),
    fmt_chart_basic(sd, "C6 scatter", "SCATTER", c(1, 7, 2, 2), list(list(range = c(1, 7, 3, 3), color = RED)),
                    anchor = slot(5), size = sz, anchor_sheet_id = dash),
    fmt_chart_waterfall(sd, "C7 waterfall totals", c(2, 7, 6, 6), c(2, 7, 7, 7), subtotal_indices = c(0L, 5L),
                        subtotal_label = "Total", data_labels = TRUE, anchor = slot(6), size = sz, anchor_sheet_id = dash),
    fmt_chart_waterfall(sd, "C8 waterfall inserted subtotal", c(2, 6, 6, 6), c(2, 6, 7, 7), subtotal_indices = 2L,
                        subtotal_labels = "Net after refunds", subtotal_is_data = FALSE,
                        anchor = slot(7), size = sz, anchor_sheet_id = dash),
    fmt_chart_pie(sd, "C9 pie", c(2, 6, 9, 9), c(2, 6, 10, 10), anchor = slot(8), size = sz, anchor_sheet_id = dash),
    fmt_chart_pie(sd, "C10 donut", c(2, 6, 9, 9), c(2, 6, 10, 10), donut = TRUE, anchor = slot(9), size = sz, anchor_sheet_id = dash),
    fmt_chart_basic(sd, "S1 styled line", "LINE", c(1, 7, 1, 1), ser2, anchor = slot(10), size = sz, anchor_sheet_id = dash,
                    x_title = "Month", y_title = "USD", y_min = 80, y_max = 200, offset_x = 40L, offset_y = 20L, style = STYLE),
    fmt_chart_pie(sd, "S2 styled donut", c(2, 6, 9, 9), c(2, 6, 10, 10), donut = TRUE, anchor = slot(11), size = sz,
                  anchor_sheet_id = dash, offset_x = 40L, offset_y = 20L, style = STYLE),
    fmt_chart_waterfall(sd, "S3 styled waterfall", c(2, 7, 6, 6), c(2, 7, 7, 7), subtotal_indices = c(0L, 5L),
                        anchor = slot(12), size = sz, anchor_sheet_id = dash, offset_x = 40L, offset_y = 20L, style = STYLE),
    fmt_chart_basic(sd, "H1 reads a column the audit hides", "COLUMN", c(1, 7, 1, 1),
                    list(list(range = c(1, 7, 12, 12), color = BLUE)), anchor = c(69L, 1L), size = sz, anchor_sheet_id = dash))
  apply_ok("14 charts of every kind in one batch (same tab and cross-tab)", charts)

  b <- api_get("sheets(properties(title),charts(chartId,border,position,spec))")
  CH <- list()
  for (s in b$sheets) for (ch in s$charts %||% list()) { ch$host <- s$properties$title; CH[[ch$spec$title]] <- ch }
  ch <- function(n) CH[[n]]
  basic <- function(n) ch(n)$spec$basicChart
  axis_of <- function(n, pos) Find(function(a) identical(a$position, pos), basic(n)$axis)
  src_sheet <- function(n) { sp <- ch(n)$spec
    src <- sp$basicChart$series[[1]]$series$sourceRange$sources[[1]] %||% sp$waterfallChart$series[[1]]$data$sourceRange$sources[[1]] %||%
      sp$pieChart$series$sourceRange$sources[[1]]
    src$sheetId %||% 0 }
  off <- function(n) c(ch(n)$position$overlayPosition$offsetXPixels %||% 0, ch(n)$position$overlayPosition$offsetYPixels %||% 0)
  subtotals <- function(n) ch(n)$spec$waterfallChart$series[[1]]$customSubtotals

  CH <- CH[vapply(CH, function(x) x$host %in% c("Data", "Dash"), NA)]               # other areas keep their own charts
  check("all 14 charts landed: 1 on Data, 13 on Dash",
        length(CH) == 14L && sum(vapply(CH, function(x) x$host == "Data", NA)) == 1L, got = names(CH))
  check("C1 LINE on its own tab, with axis titles and a fixed LEFT window 80..200",
        ch("C1 line same tab")$host == "Data" && identical(basic("C1 line same tab")$chartType, "LINE") &&
          identical(axis_of("C1 line same tab", "LEFT_AXIS")[["title"]], "USD") && identical(axis_of("C1 line same tab", "BOTTOM_AXIS")[["title"]], "Month") &&
          with(axis_of("C1 line same tab", "LEFT_AXIS")$viewWindowOptions, viewWindowMode == "EXPLICIT" && viewWindowMin == 80 && viewWindowMax == 200))
  check("cross-tab: the chart sits on Dash and reads Data (anchor_sheet_id)",
        ch("C2 stacked column")$host == "Dash" && src_sheet("C2 stacked column") == sd && (ch("C2 stacked column")$position$overlayPosition$anchorCell$sheetId %||% 0) == dash)
  check("C2 STACKED column has 2 series; C3 is an AREA chart",
        identical(basic("C2 stacked column")$stackedType, "STACKED") && length(basic("C2 stacked column")$series) == 2L &&
          identical(basic("C3 area")$chartType, "AREA"))
  check("C4 COMBO: a column series and a line series on the RIGHT axis",
        identical(basic("C4 combo")$chartType, "COMBO") && identical(basic("C4 combo")$series[[1]]$type, "COLUMN") &&
          identical(basic("C4 combo")$series[[2]]$type, "LINE") && identical(basic("C4 combo")$series[[2]]$targetAxis, "RIGHT_AXIS"))
  r <- axis_of("C4 combo", "RIGHT_AXIS")
  check("fact: Sheets DROPS RIGHT_AXIS title and view window (FAIL = Google fixed it: update charts.md, pitfalls.md)",
        is.null(r[["title"]]) && length(r$viewWindowOptions) == 0L)
  check("fmt_chart_bar: BAR chart, series on the BOTTOM axis (value axis titled)",
        identical(basic("C5 bar")$chartType, "BAR") && identical(basic("C5 bar")$series[[1]]$targetAxis, "BOTTOM_AXIS") &&
          identical(axis_of("C5 bar", "BOTTOM_AXIS")[["title"]], "USD"))
  check("C6 SCATTER", identical(basic("C6 scatter")$chartType, "SCATTER"))
  st <- subtotals("C7 waterfall totals")
  check("waterfall totals: subtotal rows 0 and 5 are data totals, data labels on",
        length(st) == 2L && identical(as.integer(unlist(lapply(st, function(x) x$subtotalIndex %||% 0L))), c(0L, 5L)) &&
          all(vapply(st, function(x) isTRUE(x$dataIsSubtotal), NA)) &&
          identical(ch("C7 waterfall totals")$spec$waterfallChart$series[[1]]$dataLabel$type, "DATA"))
  st <- subtotals("C8 waterfall inserted subtotal")
  check("waterfall subtotal_is_data = FALSE: an inserted subtotal after row 2, labelled",
        length(st) == 1L && eq(st[[1]]$subtotalIndex, 2) && !isTRUE(st[[1]]$dataIsSubtotal) && identical(st[[1]]$label, "Net after refunds"))
  check("pie has no hole; donut has pieHole 0.55", is.null(ch("C9 pie")$spec$pieChart$pieHole) &&
          isTRUE(all.equal(ch("C10 donut")$spec$pieChart$pieHole, 0.55)))
  check("plain charts carry no border, no background and no offset",
        all(vapply(c("C2 stacked column", "C9 pie", "C7 waterfall totals"), function(n)
          is.null(ch(n)$border) && is.null(ch(n)$spec$backgroundColorStyle) && all(off(n) == 0), NA)))
  sp <- ch("S1 styled line")$spec; tf <- sp$titleTextFormat
  check("style: font, title size / bold / colour / position",
        identical(sp$fontName, "Georgia") && tf$fontSize == 16 && isTRUE(tf$bold) &&
          identical(hex(tf$foregroundColorStyle$rgbColor), "#C62828") && identical(sp$titleTextPosition$horizontalAlignment, "CENTER"))
  check("style: background and border colour", identical(hex(sp$backgroundColorStyle$rgbColor), "#FFF8E1") &&
          identical(hex(ch("S1 styled line")$border$colorStyle$rgbColor), "#2457C5"))
  check("style: axis_font_size on the titled axes, window still 80..200, offset (40, 20)",
        axis_of("S1 styled line", "LEFT_AXIS")$format$fontSize == 14 && axis_of("S1 styled line", "BOTTOM_AXIS")$format$fontSize == 14 &&
          axis_of("S1 styled line", "LEFT_AXIS")$viewWindowOptions$viewWindowMax == 200 && identical(as.numeric(off("S1 styled line")), c(40, 20)))
  check("style flows to pie and waterfall: font, border, offset; the donut hole and subtotals are kept",
        all(vapply(c("S2 styled donut", "S3 styled waterfall"), function(n) identical(ch(n)$spec$fontName, "Georgia") &&
          identical(hex(ch(n)$border$colorStyle$rgbColor), "#2457C5") && identical(as.numeric(off(n)), c(40, 20)), NA)) &&
          !is.null(ch("S2 styled donut")$spec$pieChart$pieHole) && length(subtotals("S3 styled waterfall")) == 2L)

  # style validation, before any request
  pie_with <- function(style) fmt_chart_pie(1, "t", c(1, 2, 1, 1), c(1, 2, 2, 2), style = style)
  check("style: unknown key, bad colour, bad title_position, unnamed list and a font vector all stop",
        has_err(errs(pie_with(list(fnt = "Arial"))), "unknown key") && has_err(errs(pie_with(list(border = "blue"))), "hex string") &&
          has_err(errs(pie_with(list(title_position = "MIDDLE"))), "title_position") && !is.na(errs(pie_with(list("Arial")))) &&
          !is.na(errs(pie_with(list(font = c("Arial", "Georgia"))))))
  check("style: NULL and list() leave the request untouched; legend_font_size warns and is ignored",
        identical(pie_with(list()), pie_with(NULL)) && any(grepl("ignored", with_warns(pie_with(list(legend_font_size = 10)))$warnings)) &&
          identical(fmt_chart_bar(1, "t", c(1, 2, 1, 1), list(list(range = c(1, 2, 2, 2))), style = list(font = "Georgia"))$addChart$chart$spec$fontName, "Georgia"))

  # audit_chart_sources: clean, then hide a column the H1 chart reads, then restore
  audit_w <- function(...) with_warns(audit_chart_sources(SSID, ...))$warnings
  w <- c(audit_w(), audit_w(dash))
  check("audit_chart_sources: a clean sheet gives no warning, for all tabs and for one tab", length(w) == 0L, got = w)
  on.exit(try(hide_col("Data", 11L, FALSE), silent = TRUE), add = TRUE)
  hide_col("Data", 11L, TRUE)                               # column L, read only by chart H1 (on Dash)
  w <- poll(audit_w, function(w) length(w) >= 1L)
  check("audit_chart_sources: a chart on Dash reading a hidden column of Data is flagged (cross-tab)",
        length(w) >= 1L && any(grepl("H1", w, fixed = TRUE)) && all(grepl("^\\[chart QA\\]", w)), got = w)
  check("audit_chart_sources(sheet_id): only the charts that SIT on that tab", length(audit_w(sd)) == 0L && length(audit_w(dash)) >= 1L)
  hide_col("Data", 11L, FALSE)
  w <- poll(audit_w, function(w) length(w) == 0L)
  check("audit_chart_sources: clean again once the column is visible", length(w) == 0L, got = w)
  check("audit_chart_sources: an HTTP error stops instead of passing as clean", !is.na(errs(audit_chart_sources("not-a-real-id"))))
}

# ── Area: modern (slicer, protections, filters, pivot) ---------------------------

area_modern <- function() {
  t <- "Modern"
  gs_reset_tabs(ss, t)
  s <- sid(t)
  write_block(ss, t, 1, 1, rbind(c("Item", "Type", "Month", "Amount")))
  write_block(ss, t, 2, 1, data.frame(i = c("Rent", "Pay", "Food", "Fun", "Pay", "Rent", "Food"),
                                      y = c("Expense", "Income", "Expense", "Expense", "Income", "Expense", "Expense"),
                                      m = c("Jan", "Jan", "Jan", "Feb", "Feb", "Feb", "Feb"),
                                      a = c(1200, 3000, 400, 150, 3000, 1200, 380)))
  flush_writes(ss, strict = TRUE)
  apply_ok("filter, slicer, filter view, 2 protections and 2 pivots in one batch", list(
    fmt_basic_filter(s, 1, 8, 1, 4),
    fmt_slicer(s, s, c(1, 8, 1, 4), column_index = 1L, anchor_row = 11, anchor_col = 1, title = "Type", size = c(220L, 34L)),
    fmt_filter_view(s, 1, 8, 1, 4, title = "Expenses", sort_specs = list(list(dimensionIndex = 3L, sortOrder = "DESCENDING")),
                    criteria = list("1" = list(hiddenValues = list("Income")))),
    fmt_protected_range(s, description = "whole sheet", unprotected_ranges = list(grid_range(s, 2, 3, 4, 4))),
    fmt_protected_range(s, 1, 1, 1, 4, description = "header"),
    fmt_pivot_table(s, 1, 7, s, c(1, 8, 1, 4), rows = list(list(sourceColumnOffset = 1L)),     # no sortOrder: defaulted
                    values = list(list(sourceColumnOffset = 3L, summarizeFunction = "SUM", name = "Total"))),
    fmt_pivot_table(s, 1, 12, s, c(1, 8, 1, 4), rows = list(list(sourceColumnOffset = 1L)),
                    values = list(list(sourceColumnOffset = 3L, summarizeFunction = "SUM", name = "Total")),
                    filters = list("1" = list(visibleValues = list("Expense"))))))

  sh <- tab_of(api_get("sheets(properties(title),slicers(slicerId,spec),protectedRanges(range,unprotectedRanges,description),filterViews(title,sortSpecs,criteria),basicFilter(range))"), t)
  check("fmt_slicer: one slicer on column 1, titled, coexisting with the basic filter",
        length(sh$slicers) == 1L && sh$slicers[[1]]$spec$columnIndex == 1L && identical(sh$slicers[[1]]$spec$title, "Type") && !is.null(sh$basicFilter))
  whole <- Filter(function(p) is.null(p$range$startRowIndex), sh$protectedRanges)
  check("fmt_protected_range: whole sheet with one unprotected hole, and a bounded range",
        length(sh$protectedRanges) == 2L && length(whole) == 1L && length(whole[[1]]$unprotectedRanges) == 1L)
  check("fmt_filter_view: titled, sorted descending, hides 'Income' on column 1",
        length(sh$filterViews) == 1L && identical(sh$filterViews[[1]]$title, "Expenses") &&
          identical(sh$filterViews[[1]]$sortSpecs[[1]]$sortOrder, "DESCENDING") && !is.null(sh$filterViews[[1]]$criteria[["1"]]))
  pivot <- function(a1) { m <- read_values(ss, a1, "UNFORMATTED_VALUE")[[1]]      # header row, then one row per Type
    if (nrow(m) < 2L) numeric() else stats::setNames(as.numeric(m[-1, 2]), m[-1, 1]) }
  p1 <- poll(function() pivot("Modern!G1:H8"), function(x) length(x) >= 2L)
  p2 <- poll(function() pivot("Modern!L1:M8"), function(x) length(x) >= 1L)
  check("fmt_pivot_table: rows by Type, SUM of Amount (Expense 3330, Income 6000)", identical(p1, c(Expense = 3330, Income = 6000)), got = p1)
  check("fmt_pivot_table(filters): only the 'Expense' row (3330)", identical(p2, c(Expense = 3330)), got = p2)
}

# ── Area: rules (conditional formats, validation, dropdowns) ----------------------

area_rules <- function() {
  t <- "Rules"
  gs_reset_tabs(ss, t)
  s <- sid(t)
  txt <- data.frame(t = c("Done", "Not done", "Done early", "DONE", "alpha", "Beta", "Doneness", NA))
  for (cc in 1:4) write_block(ss, t, 1, cc, txt)
  write_block(ss, t, 1, 5, data.frame(n = c(1, 5, 9, 2, 7, 4, 8, -3)))
  write_block(ss, t, 1, 7, data.frame(n = c(10, 20, 30, 40, 50, 60, 70, 80)))
  flush_writes(ss, strict = TRUE)

  GREEN <- COL_GREEN_LIGHT
  rules <- list(                                                                  # index = priority, listed first = wins
    fmt_cond_formula(s, 1, 8, 6, 6, "=$E1>5", bg_color = COL_YELLOW_LIGHT, index = 0L),
    fmt_cond_text_equals(s, 1, 8, 1, 1, "done", bg_color = GREEN, index = 1L),
    fmt_cond_text(s, 1, 8, 2, 2, op = "starts_with", text = "done", bg_color = GREEN, index = 2L),
    fmt_cond_text(s, 1, 8, 3, 3, op = "contains", text = "DONE", bg_color = GREEN, index = 3L),
    fmt_cond_text(s, 1, 8, 4, 4, op = "not_contains", text = "a", bg_color = GREEN, index = 4L),
    fmt_cond_number(s, 1, 8, 5, 5, 5, "greater", bg_color = COL_RED_LIGHT, index = 5L),
    fmt_cond_color_scale(s, 1, 8, 7, 7, index = 6L),
    fmt_cond_number(s, 1, 8, 8, 8, 0, "less_eq", bg_color = COL_BLUE_LIGHT),        # default index 0: lands first
    fmt_cond_negative(s, 1, 8, 5, 5))                                                # index 0 as well: lands first of all
  dv <- list(
    fmt_validation(s, 1, 1, 10, 10, "NUMBER_BETWEEN", c(0, 1), input_message = "A rate from 0 to 1."),
    fmt_validation(s, 2, 2, 10, 10, "NUMBER_GREATER_THAN_EQ", 0, strict = FALSE),
    fmt_validation(s, 3, 3, 10, 10, "DATE_IS_VALID", input_message = "Enter a date."),
    fmt_validation(s, 4, 4, 10, 10, "DATE_BEFORE", as.Date("2030-01-01")),
    fmt_validation(s, 5, 5, 10, 10, "DATE_AFTER", "=TODAY()"),
    fmt_validation(s, 6, 6, 10, 10, "CUSTOM_FORMULA", "=AND(ISNUMBER(J6),J6>0)"),
    fmt_validation(s, 7, 7, 10, 10, "TEXT_CONTAINS", "ok"),
    fmt_validation(s, 8, 8, 10, 10, "DATE_BETWEEN", c("2026-01-01", "2026-12-31")),
    fmt_validation(s, 9, 9, 10, 10, "TEXT_IS_EMAIL"),
    fmt_dropdown(s, 1, 3, 12, 12, c("Open", "Done"), input_message = "Pick one"),
    fmt_dropdown_range(s, 1, 3, 13, 13, "=Rules!$A$1:$A$7", input_message = "From the list"))
  apply_ok("9 conditional rules, 9 validation rules and 2 dropdowns in one batch", c(rules, dv))

  b <- api_get("sheets(properties(title),conditionalFormats(booleanRule(condition(type)),gradientRule(minpoint(type))))")
  cf <- tab_of(b, t)$conditionalFormats
  types <- vapply(cf, function(r) if (!is.null(r$booleanRule)) r$booleanRule$condition$type else "GRADIENT", "")
  check("rule priority: explicit index 0..6 keep their order; later default-index rules land on top",
        identical(types, c("NUMBER_LESS", "NUMBER_LESS_THAN_EQ", "CUSTOM_FORMULA", "TEXT_EQ", "TEXT_STARTS_WITH",
                           "TEXT_CONTAINS", "TEXT_NOT_CONTAINS", "NUMBER_GREATER", "GRADIENT")), got = types)

  g <- grid(t, "A1:M9")
  bg <- function(col, n = 8L) vapply(seq_len(n), function(r) hex(cell_at(g, r, col)$effectiveFormat$backgroundColor), "")
  lit <- function(col, hexcol) which(bg(col) == hexcol)
  gh <- color_to_hex(GREEN)
  check("behaviour: equals 'done' lights Done and DONE (case-insensitive)", identical(lit(1, gh), c(1L, 4L)), got = lit(1, gh))
  check("behaviour: starts_with 'done' lights Done, Done early, DONE, Doneness", identical(lit(2, gh), c(1L, 3L, 4L, 7L)), got = lit(2, gh))
  check("behaviour: contains 'DONE' matches ignoring case", identical(lit(3, gh), c(1L, 2L, 3L, 4L, 7L)), got = lit(3, gh))
  check("behaviour: not_contains 'a' also lights the EMPTY cell (row 8)", identical(lit(4, gh), c(1L, 2L, 4L, 7L, 8L)), got = lit(4, gh))
  check("behaviour: number rule > 5 and the custom-formula rule light rows 3, 5, 7",
        identical(lit(5, color_to_hex(COL_RED_LIGHT)), c(3L, 5L, 7L)) && identical(lit(6, color_to_hex(COL_YELLOW_LIGHT)), c(3L, 5L, 7L)))
  check("behaviour: fmt_cond_negative turns the -3 red", identical(hex(cell_at(g, 8, 5)$effectiveFormat$textFormat$foregroundColorStyle$rgbColor %||%
          cell_at(g, 8, 5)$effectiveFormat$textFormat$foregroundColor), color_to_hex(COL_RED_TEXT)))
  check("behaviour: the colour scale shades the lowest and highest differently", !identical(bg(7)[1], bg(7)[8]), got = bg(7)[c(1, 8)])

  v <- function(r) cell_at(g, r, 10)$dataValidation
  uv <- function(r) vapply(v(r)$condition$values, function(x) x$userEnteredValue %||% "?", "")
  check("fmt_validation: types read back in order",
        identical(vapply(1:9, function(r) v(r)$condition$type, ""),
                  c("NUMBER_BETWEEN", "NUMBER_GREATER_THAN_EQ", "DATE_IS_VALID", "DATE_BEFORE", "DATE_AFTER",
                    "CUSTOM_FORMULA", "TEXT_CONTAINS", "DATE_BETWEEN", "TEXT_IS_EMAIL")))
  check("fmt_validation: values, Date and formula values, custom formula, date range",
        identical(uv(1), c("0", "1")) && identical(uv(4), "2030-01-01") && identical(uv(5), "=TODAY()") &&
          identical(uv(6), "=AND(ISNUMBER(J6),J6>0)") && identical(uv(8), c("2026-01-01", "2026-12-31")))
  check("fmt_validation: input_message and strict (TRUE default, FALSE on request)",
        identical(v(1)$inputMessage, "A rate from 0 to 1.") && isTRUE(v(1)$strict) && !isTRUE(v(2)$strict))
  check("fmt_dropdown: ONE_OF_LIST with a hint; fmt_dropdown_range: ONE_OF_RANGE",
        identical(cell_at(g, 1, 12)$dataValidation$condition$type, "ONE_OF_LIST") &&
          length(cell_at(g, 1, 12)$dataValidation$condition$values) == 2L && identical(cell_at(g, 1, 12)$dataValidation$inputMessage, "Pick one") &&
          identical(cell_at(g, 1, 13)$dataValidation$condition$type, "ONE_OF_RANGE"))

  write_block(ss, t, 1, 10, rbind("abc"))                                          # J1 allows only 0..1
  flush_writes(ss, strict = TRUE)
  g2 <- grid(t, "J1:J1")
  check("fact: a value written through the API BYPASSES the validation rule (the rule stays on the cell)",
        identical(read_values(ss, "Rules!J1")[[1]][1, 1], "abc") && identical(cell_at(g2, 1, 1)$dataValidation$condition$type, "NUMBER_BETWEEN"))

  check("count_cond_rules counts the 9 rules", count_cond_rules(SSID, s) == 9L)
  del <- fmt_delete_cond_rules(SSID, s)
  check("fmt_delete_cond_rules returns one delete per rule, descending; an empty tab gives list()",
        length(del) == 9L && del[[1]]$deleteConditionalFormatRule$index == 8L && length(fmt_delete_cond_rules(SSID, sid("Q1"))) == 0L)
  apply_ok("deleting all the rules in one batch", del)
  check("count_cond_rules is 0 afterwards", count_cond_rules(SSID, s) == 0L)
}

# ── Area: formulas (f_* builders evaluated by Sheets) ---------------------------

area_formulas <- function() {
  t <- "Formulas"
  gs_reset_tabs(ss, t)
  write_block(ss, t, 1, 2, rbind(c(3, 5, 2, 8)))                                    # B1:E1
  write_block(ss, t, 3, 1, rbind(c("cat", "region", "amt")))
  write_block(ss, t, 4, 1, data.frame(a = c("x", "x", "y", "y"), b = c("n", "s", "n", "s"), c = c(10, 20, 5, 1)))
  write_cell(ss, t, 1, 6, f_sparkline("B1:E1", list(charttype = "line", linewidth = 2, color = color_to_hex(hex_to_color("2457C5")))))
  write_cell(ss, t, 2, 6, '=SPARKLINE(B1:E1, {"charttype","line";"linewidth","2"})')
  write_cell(ss, t, 3, 6, f_sparkline("H1:K1", list(charttype = "line")))
  write_cell(ss, t, 4, 6, f_sparkline("H1:K1", list(charttype = "line"), iferror = TRUE))
  write_cell(ss, t, 5, 6, f_sumifs("Formulas!C4:C7", list("Formulas!A4:A7" = "x")))
  write_cell(ss, t, 6, 6, f_sumifs("Formulas!C4:C7", list(c("Formulas!A4:A7", "y"), c("Formulas!B4:B7", "n"))))
  write_cell(ss, t, 7, 6, f_safe_div("C4", "C8"))
  write_cell(ss, t, 8, 6, f_safe_div("C4", "C5"))
  write_cell(ss, t, 9, 6, f_iferror("=1/0", '"n/a"'))
  write_cell(ss, t, 10, 6, f_named("={a}*{b}", a = "C4", b = "C5"))
  write_cell(ss, t, 11, 6, sprintf("=%s+%s", fraw(f_sumifs("C4:C7", list("A4:A7" = "x"))), fraw(f_sumifs("C4:C7", list("A4:A7" = "y")))))
  write_cell(ss, t, 12, 6, f_sumifs("Formulas!C4:C7", list("Formulas!C4:C7" = ">5")))
  write_cell(ss, t, 3, 9, f_query("Formulas!A3:C7", "select A, sum(C) where A = 'x' group by A", 1L))   # spills I3:J4
  flush_writes(ss, strict = TRUE)
  g <- grid(t, "A1:J12")
  fv <- function(r, c = 6) cell_at(g, r, c)$formattedValue %||% ""
  err <- function(r, c = 6) !is.null(cell_at(g, r, c)$effectiveValue$errorValue)
  check("f_sparkline: a numeric linewidth evaluates without an error", !err(1) && nzchar(cell_at(g, 1, 6)$userEnteredValue$formulaValue))
  check("fact: a QUOTED linewidth (\"linewidth\",\"2\") is an error in Sheets, which is why options keep their type", err(2))
  check("f_sparkline(iferror = TRUE): an empty source shows nothing instead of an error", !err(4) && identical(fv(4), ""))
  check("fact: the same SPARKLINE over an empty range WITHOUT iferror is an error", err(3))
  check("f_sumifs: named criteria = 30, pair list = 5", identical(fv(5), "30") && identical(fv(6), "5"))
  check("f_safe_div: '' on a zero denominator, the ratio otherwise", identical(fv(7), "") && identical(fv(8), "0.5"))
  check("f_iferror falls back to its text; f_named multiplies the cells; fraw lets two builders combine",
        identical(fv(9), "n/a") && identical(fv(10), "200") && identical(fv(11), "36"))
  check("f_sumifs with an operator criterion (\">5\") evaluates (10 + 20 = 30)", identical(fv(12), "30"), got = fv(12))
  check("f_query: filters and groups (x -> 30)", identical(fv(4, 9), "x") && identical(fv(4, 10), "30"), got = c(fv(3, 9), fv(4, 9), fv(4, 10)))
}

# ── Area: tabs (order, theme) ---------------------------------------------------

area_tabs <- function() {
  ord <- function() googlesheets4::sheet_properties(ss)$name
  on.exit(try(batch_format(ss, fmt_tab_order(NULL, unname(IDS[TABS])), strict = TRUE), silent = TRUE), add = TRUE)   # leave the order as TABS
  start <- ord()
  apply_ok("fmt_tab_order(ss, names): two tabs first", fmt_tab_order(ss, c("Dash", "Data")))
  check("fmt_tab_order: the listed tabs come first, the others keep their relative order",
        identical(ord(), c("Dash", "Data", setdiff(start, c("Dash", "Data")))), got = ord())
  apply_ok("fmt_tab_order(NULL, sheetIds): numeric ids need no lookup", fmt_tab_order(NULL, unname(IDS[TABS])))
  check("...and restores the original order", identical(ord(), TABS), got = ord())
  check("fmt_tab_order: an unknown tab stops before any request", has_err(errs(fmt_tab_order(ss, c("Data", "Nope"))), "no such tab"))
  check("fmt_tab_order returns a list of requests that mixes with other requests via c()",
        length(c(list(fmt_freeze(1L, 1L)), fmt_tab_order(NULL, c(1, 2)))) == 3L)

  theme <- function() { th <- api_get("properties.spreadsheetTheme")$properties$spreadsheetTheme
    list(colors = stats::setNames(vapply(th$themeColors, function(x) sub("^#", "", hex(x$color$rgbColor)), ""),
                                  vapply(th$themeColors, function(x) x$colorType, "")), font = th$primaryFontFamily) }
  pal <- c(accent1 = "C0392B", accent2 = "27AE60", accent3 = "2980B9", accent4 = "F39C12", accent5 = "8E44AD", accent6 = "16A085")
  on.exit(try(batch_format(ss, list(fmt_theme_colors()), strict = TRUE), silent = TRUE), add = TRUE)                    # and the default theme
  apply_ok("fmt_theme_colors: accents, link and font in one request", list(do.call(fmt_theme_colors, c(as.list(pal), list(link = "0B57D0", font_family = "Verdana")))))
  th <- theme()
  check("fmt_theme_colors: ACCENT1..6, LINK and the font read back",
        identical(unname(th$colors[paste0("ACCENT", 1:6)]), unname(pal)) && identical(th$colors[["LINK"]], "0B57D0") && identical(th$font, "Verdana"))
  apply_ok("fmt_theme_colors() with no arguments restores Google's default theme", list(fmt_theme_colors()))
  th <- theme()
  check("...ACCENT1..6, TEXT, BACKGROUND, LINK and Arial are Google's defaults again",
        identical(unname(th$colors[c(paste0("ACCENT", 1:6), "TEXT", "BACKGROUND", "LINK")]),
                  c("4285F4", "EA4335", "FBBC04", "34A853", "FF6D01", "46BDC6", "000000", "FFFFFF", "1155CC")) && identical(th$font, "Arial"), got = th)
}

# ── Area: guard (gs_reset_tabs, gs_open_or_create title guard, idempotent rebuilds) ---

# One of every object gs_reset_tabs must unwind, on `tab`.
kitchen <- function(tab) {
  gs_reset_tabs(ss, tab)
  s <- sid(tab)
  write_block(ss, tab, 1, 1, rbind(c("Item", "Qty")))
  write_block(ss, tab, 2, 1, data.frame(i = c("a", "b", "c", "d"), q = c(1, 2, 3, 4)))
  flush_writes(ss, strict = TRUE)
  batch_format(ss, c(
    list(fmt_cells(s, 1, 1, 1, 2, bold = TRUE, bg_color = COL_BLUE_LIGHT), fmt_freeze(s, rows = 1L),
         fmt_col_width(s, 1, 1, 220), fmt_row_height(s, 2, 2, 40),
         fmt_cond_formula(s, 2, 5, 2, 2, "=$B2>2", bg_color = COL_RED_LIGHT),
         fmt_validation(s, 2, 5, 2, 2, "NUMBER_BETWEEN", c(0, 10)), fmt_dropdown(s, 2, 5, 4, 4, c("a", "b")),
         fmt_merge(s, 8, 8, 1, 3), fmt_basic_filter(s, 1, 5, 1, 2), fmt_banding(s, 10, 14, 1, 2),
         fmt_named_range(s, paste0("ST_", gsub("[^A-Za-z]", "", tab)), 2, 5, 2, 2),
         fmt_protected_range(s, 2, 3, 1, 1, description = "selftest"),
         fmt_filter_view(s, 1, 5, 1, 2, title = "selftest view"),
         fmt_slicer(s, s, c(1, 5, 1, 2), 0L, 16, 1, title = "selftest slicer"),
         fmt_chart_basic(s, "selftest chart", "COLUMN", c(1, 5, 1, 1), list(list(range = c(1, 5, 2, 2))), anchor = c(24L, 1L)),
         fmt_pivot_table(s, 1, 12, s, c(1, 5, 1, 2), rows = list(list(sourceColumnOffset = 0L)),
                         values = list(list(sourceColumnOffset = 1L, summarizeFunction = "SUM", name = "Q"))),
         list(updateCells = list(rows = list(list(values = list(list(note = "a note")))), fields = "note",
                                 start = list(sheetId = s, rowIndex = 1L, columnIndex = 1L)))),
    fmt_group_rows(s, 20, 21), fmt_group_cols(s, 9, 10)), strict = TRUE)
}
# Object counts of a tab (one spreadsheets.get) and cell-level counts (one more).
counts_of <- function(tab) {
  b <- api_get(paste0("namedRanges(range),sheets(properties(title,sheetId,gridProperties(frozenRowCount)),charts(chartId),",
                      "slicers(slicerId),protectedRanges(protectedRangeId),filterViews(filterViewId),conditionalFormats(ranges),",
                      "bandedRanges(bandedRangeId),merges,rowGroups,columnGroups,basicFilter(range))"))
  sh <- tab_of(b, tab); id <- sh$properties$sheetId %||% 0
  c(charts = length(sh$charts), slicers = length(sh$slicers), protected = length(sh$protectedRanges),
    views = length(sh$filterViews), cond = length(sh$conditionalFormats), banded = length(sh$bandedRanges),
    merges = length(sh$merges), rowgroups = length(sh$rowGroups), colgroups = length(sh$columnGroups),
    filter = as.integer(!is.null(sh$basicFilter)), named = sum(vapply(b$namedRanges, function(n) (n$range$sheetId %||% 0) == id, NA)),
    frozen = sh$properties$gridProperties$frozenRowCount %||% 0L)
}
cells_of <- function(tab) {
  cells <- unlist(lapply(grid(tab, "A1:M30", "userEnteredValue,dataValidation,note,pivotTable"), function(r) r$values), recursive = FALSE)
  c(values = sum(vapply(cells, function(x) !is.null(x$userEnteredValue), NA)), validation = sum(vapply(cells, function(x) !is.null(x$dataValidation), NA)),
    notes = sum(vapply(cells, function(x) !is.null(x$note), NA)), pivots = sum(vapply(cells, function(x) !is.null(x$pivotTable), NA)))
}

area_guard <- function() {
  e <- errs(kitchen("Keep"))
  check("kitchen build (one of every object type) on the tab that must survive", is.na(e), got = e)
  k_obj <- counts_of("Keep"); k_cell <- cells_of("Keep")
  check("...every object type is present", all(k_obj >= 1L) && all(k_cell >= 1L), got = c(k_obj, k_cell))
  keep_same <- function() identical(counts_of("Keep"), k_obj) && identical(cells_of("Keep"), k_cell)

  e <- c(errs(gs_reset_tabs(ss)), errs(gs_reset_tabs(ss, NULL)), errs(gs_reset_tabs(ss, NA_character_)), errs(gs_reset_tabs(ss, character(0))))
  check("gs_reset_tabs: no tabs / NULL / NA / empty stop with '`tabs` is required'", all(vapply(e, has_err, NA, "`tabs` is required")), got = e)
  check("gs_reset_tabs: an unknown tab stops with 'no such tab'", has_err(errs(gs_reset_tabs(ss, c("Keep", "NoSuchTab"))), "no such tab"))
  check("...and nothing was wiped", keep_same())

  e <- errs(kitchen("Wipe")); a <- c(counts_of("Wipe"), cells_of("Wipe"))
  e2 <- errs(kitchen("Wipe")); b <- c(counts_of("Wipe"), cells_of("Wipe"))
  check("gs_reset_tabs is idempotent: the build run twice raises no HTTP 400", is.na(e) && is.na(e2), got = c(e, e2))
  check("...and both runs leave identical object counts, every type present", identical(a, b) && all(a >= 1L), got = rbind(a, b))

  gs_reset_tabs(ss, "Wipe", keep_values = TRUE)
  kv <- c(counts_of("Wipe"), cells_of("Wipe"))
  check("keep_values = TRUE: values and the named range stay, objects / validation / notes / pivots go",
        kv[["values"]] == a[["values"]] && kv[["named"]] == 1L && kv[["validation"]] == 0L && kv[["notes"]] == 0L && kv[["pivots"]] == 0L &&
          all(kv[c("charts", "slicers", "protected", "views", "cond", "banded", "merges", "rowgroups", "colgroups", "filter", "frozen")] == 0L), got = kv)

  gs_reset_tabs(ss, "Wipe")
  z <- c(counts_of("Wipe"), cells_of("Wipe"))
  check("gs_reset_tabs wipes every object, the named range and every value on the named tab", all(z == 0L), got = z)
  check("...and leaves the other tab untouched", keep_same())
  d <- api_get("sheets(data(rowMetadata(pixelSize,hiddenByUser),columnMetadata(pixelSize,hiddenByUser)))", ranges = "Wipe!A1:K25")$sheets[[1]]$data[[1]]
  check("...and resets sizes (100px columns, 21px rows) and un-hides the grouped rows and columns",
        d$columnMetadata[[1]]$pixelSize == 100 && d$rowMetadata[[2]]$pixelSize == 21 &&
          !any(vapply(c(d$rowMetadata, d$columnMetadata), function(x) isTRUE(x$hiddenByUser), NA)))

  # the title guard of gs_open_or_create
  snap <- function() { have <- googlesheets4::gs4_get(ss); list(title = have$name, tabs = have$sheets$name, keep = read_values(ss, "Keep!A1:B5")[[1]]) }
  s0 <- snap()
  e <- errs(gs_open_or_create("Some other title", "NoSuchTab", id = SSID))
  check("title guard: a mismatched id stops, naming both titles", has_err(e, TITLE) && has_err(e, "Some other title") && has_err(e, "Nothing was changed"), got = e)
  check("...with nothing changed (title, tabs, values)", identical(snap(), s0))
  check("title guard: the matching title passes", is.na(errs(gs_open_or_create(TITLE, c("Keep", "Wipe"), id = SSID))))
  check("title guard: another title passes when the file has ALL the tabs (a renamed copy)",
        is.na(errs(gs_open_or_create("Some other title", c("Keep", "Wipe"), id = SSID))) && identical(snap(), s0))
  e <- errs(gs_open_or_create("Some other title", "GuardNew", id = SSID, allow_mismatch = TRUE, rows = c(GuardNew = 40), cols = c(GuardNew = 5)))
  p <- googlesheets4::sheet_properties(ss)
  check("allow_mismatch = TRUE reuses any file (adds the missing tab); the title is untouched",
        is.na(e) && "GuardNew" %in% p$name && identical(googlesheets4::gs4_get(ss)$name, TITLE), got = e)
  check("gs_open_or_create(rows, cols) sizes the tab (40 x 5)",
        p$grid_rows[p$name == "GuardNew"] == 40L && p$grid_columns[p$name == "GuardNew"] == 5L)
  googlesheets4::sheet_delete(ss, "GuardNew")
  check("...and the scratch tab is gone again", setequal(googlesheets4::sheet_properties(ss)$name, TABS))
}

# ── Area: qa (visibility audits, dump, layout audit, PDF export) -------------------

area_qa <- function() {
  q <- sid("Q1")
  on.exit(try(hide_col("Q1", 0L, FALSE), silent = TRUE), add = TRUE)
  check("first_visible_col: 1 when column A is visible", first_visible_col(SSID, q) == 1L)
  hide_col("Q1", 0L, TRUE)
  check("first_visible_col: 2 once column A is hidden", identical(poll(function() first_visible_col(SSID, q), function(x) x == 2L), 2L))
  check("audit_merge: hidden columns do not count (A hidden + B = 100px)",
        isTRUE(audit_merge(SSID, q, 1, 2, min_visible_px = 80L)) && !isTRUE(audit_merge(SSID, q, 1, 1, 80L)) && !isTRUE(audit_merge(SSID, q, 1, 2, 150L)))
  hide_col("Q1", 0L, FALSE)

  f <- tempfile(fileext = ".txt")
  dump_reference_tab(SSID, "Cells", "A1:N30", f)
  d <- readLines(f); unlink(f)
  check("dump_reference_tab: tab header, MERGE lines, cell lines with format", any(grepl("^# tab=Cells frozenRows=1", d)) &&
          sum(grepl("^MERGE", d)) == 3L && any(grepl("^R1 C1 \\| \"Header\" \\| bg=#2457C5 fg=#FFFFFF B-", d)), got = head(d, 3))

  if (requireNamespace("dplyr", quietly = TRUE) && requireNamespace("tibble", quietly = TRUE)) {
    a <- audit_layout(ss, "Cells")
    check("audit_layout returns a findings table (zero rows = clean)", is.data.frame(a), got = class(a))
  } else skip("audit_layout", "needs the dplyr and tibble packages")

  pdf <- tempfile(fileext = ".pdf")
  e <- errs(export_sheet_as_pdf(ss, "Dash", pdf))
  check("export_sheet_as_pdf: a real PDF from the Dash tab (at the default level)",
        is.na(e) && file.exists(pdf) && identical(readBin(pdf, "raw", 4L), charToRaw("%PDF")) && file.size(pdf) > 2000, got = e)
  if (nzchar(Sys.which("pdftoppm")) || requireNamespace("pdftools", quietly = TRUE)) {
    png <- no_poppler_noise(pdf_to_pngs(pdf))
    check("pdf_to_pngs: one PNG per page", length(png) >= 1L && all(file.exists(png)), got = png)
    unlink(png)
  } else skip("pdf_to_pngs", "needs pdftoppm (poppler) or the pdftools package")
  unlink(pdf)

  if (requireNamespace("dplyr", quietly = TRUE) && requireNamespace("tibble", quietly = TRUE)) {
    out_dir <- tempfile("vqa")
    v <- NULL
    e <- errs(v <- no_poppler_noise(visual_qa(ss, "Cells", out_dir = out_dir, pause_s = 0)))
    check("visual_qa: findings table, one PDF and its page images for the tab",
          is.na(e) && is.data.frame(v$findings) && file.exists(v$pdfs[["Cells"]]), got = e)
    unlink(out_dir, recursive = TRUE)
  } else skip("visual_qa", "needs the dplyr and tibble packages")
}

# ── Area: minimal (examples/minimal.R end to end) ----------------------------------

area_minimal <- function() {
  gs_reset_tabs(ss, "Summary")
  old <- Sys.getenv(c("SHEET_ID", "GS_SKILL_DIR"), unset = NA)
  Sys.setenv(SHEET_ID = SSID, GS_SKILL_DIR = SKILL)
  on.exit({ Sys.unsetenv("SHEET_ID"); refresh_ids() }, add = TRUE)
  out <- character()
  e <- errs(out <- utils::capture.output(source(file.path(SKILL, "examples", "minimal.R"), local = new.env(), echo = FALSE)))
  check("examples/minimal.R runs end to end against the scratch sheet (SHEET_ID reuse; the title guard lets it in because the tab exists)",
        is.na(e), got = e)
  check("...its own post-build QA passed and it printed the sheet URL", any(grepl("[QA] post-build checks passed", out, fixed = TRUE)) && any(grepl("^Sheet URL: ", out)))
  b <- api_get("sheets(properties(title,gridProperties(frozenRowCount,hideGridlines)),data(rowData(values(formattedValue,userEnteredFormat(textFormat)))))",
               ranges = "Summary!A1:K7")
  sh <- tab_of(b, "Summary"); rows <- sh$data[[1]]$rowData
  check("...the data landed (header 'mpg', 6 rows of mtcars)", identical(cell_at(rows, 1, 1)$formattedValue, "mpg") && length(rows) == 7L)
  check("...the header is bold, the row frozen and the gridlines hidden",
        isTRUE(text_fmt(cell_at(rows, 1, 1))$bold) && sh$properties$gridProperties$frozenRowCount == 1 && isTRUE(sh$properties$gridProperties$hideGridlines))
}

# ── Run ---------------------------------------------------------------------------

t_start <- Sys.time()
ACCT <- quiet(gs_connect(quiet = TRUE))

sel <- Sys.getenv("SELFTEST_SHEET_ID", "")
if (nzchar(sel)) {
  have <- googlesheets4::gs4_get(googlesheets4::as_sheets_id(sel))
  if (!identical(have$name, TITLE))
    stop("selftest: SELFTEST_SHEET_ID is a file titled '", have$name, "', not '", TITLE, "'. The test wipes tabs, ",
         "so it only runs on its own scratch sheet. Unset SELFTEST_SHEET_ID to create one.", call. = FALSE)
}
ss <- quiet(gs_open_or_create(TITLE, TABS, id = sel))
SSID <- as.character(ss)
if (!nzchar(sel)) cat("Created the scratch sheet. Reuse with SELFTEST_SHEET_ID=", SSID, "\n", sep = "")
# A run that failed half way (or a broken helper) can leave a stray tab behind: remove it, so every run starts the same.
extra <- setdiff(googlesheets4::sheet_names(ss), TABS)
for (tab in extra) quiet(googlesheets4::sheet_delete(ss, tab))
if (length(extra)) cat("Removed leftover tab(s) from an earlier run: ", paste(extra, collapse = ", "), "\n", sep = "")
refresh_ids()

AREAS <- list(offline = area_offline, auth = area_auth, cells = area_cells, writes = area_writes, charts = area_charts,
              modern = area_modern, rules = area_rules, formulas = area_formulas, tabs = area_tabs,
              guard = area_guard, qa = area_qa, minimal = area_minimal)
only <- trimws(strsplit(Sys.getenv("SELFTEST_ONLY", ""), ",", fixed = TRUE)[[1]])
if (length(only) && !all(only %in% names(AREAS)))
  stop("selftest: SELFTEST_ONLY names an unknown area. Areas: ", paste(names(AREAS), collapse = ", "), call. = FALSE)

cat(sprintf("\nr-googlesheets4 selftest | skill: %s | scratch sheet: %s\n\n", SKILL, SSID))
cat(sprintf("%-4s  %-8s  %s\n", "", "area", "check"))
secs <- numeric()
for (nm in names(AREAS)) {
  if (length(only) && !nm %in% only) next
  AREA <- nm; t0 <- Sys.time()
  tryCatch(quiet(withCallingHandlers(AREAS[[nm]](), warning = function(w) invokeRestart("muffleWarning"))),
           error = function(e) record("FAIL", "area stopped before its last check", conditionMessage(e)))
  secs[nm] <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
}

# ── Summary -------------------------------------------------------------------------

st <- vapply(RESULTS, function(r) r$status, "")
ar <- vapply(RESULTS, function(r) r$area, "")
cat("\n", sprintf("%-9s %5s %5s %5s %7s\n", "area", "PASS", "FAIL", "SKIP", "secs"), sep = "")
for (nm in names(secs))
  cat(sprintf("%-9s %5d %5d %5d %7.0f\n", nm, sum(st == "PASS" & ar == nm), sum(st == "FAIL" & ar == nm), sum(st == "SKIP" & ar == nm), secs[[nm]]))
total <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
cat(sprintf("\n%d PASS, %d FAIL, %d SKIP in %.0f s (%.1f min)\n", sum(st == "PASS"), sum(st == "FAIL"), sum(st == "SKIP"), total, total / 60))
if (any(st == "FAIL")) {
  cat("FAILED:\n")
  for (r in RESULTS) if (r$status == "FAIL") cat(sprintf("  [%s] %s\n", r$area, r$label))
  quit(save = "no", status = 1L)
}
cat("ALL CHECKS PASSED\n")
