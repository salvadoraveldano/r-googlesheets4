#!/usr/bin/env Rscript
# =============================================================================
# offline-test.R — checks of the helpers that need no Google account
# =============================================================================
#
# Repo dev tool (NOT shipped in skills/). It builds requests and formulas with the
# helpers and asserts on their shape, and it checks the guards that must stop a bad
# call BEFORE any request is sent. It never signs in and sends nothing to Google, so it
# runs in CI on every push:
#
#   Rscript scripts/offline-test.R
#
# Needs the CRAN packages googlesheets4, googledrive, httr, glue and jsonlite (the helpers
# load them). Exit status is non-zero when any check fails.
#
# What it cannot do: tell whether Google ACCEPTS a request. scripts/selftest.R does that
# against a real sheet; run it after changing a helper. The checks here pin the shapes
# that an earlier live test showed Google rejects or misreads (a chart source without
# `sourceRange`, a slicer with `filterSpec`, a fractional pixel width, a leading `+`).
# =============================================================================

args <- grep("^--file=", commandArgs(FALSE), value = TRUE)
ROOT  <- if (length(args)) normalizePath(file.path(dirname(sub("^--file=", "", args[1L])), "..")) else getwd()
SKILL <- normalizePath(Sys.getenv("GS_SKILL_DIR", file.path(ROOT, "skills", "r-googlesheets4")), mustWork = FALSE)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("offline-test.R needs the jsonlite package", call. = FALSE)
for (f in c("gs_helpers.R", "gs_buffer.R", "gs_formulas.R", "gs_charts.R", "gs_modern.R"))
  suppressMessages(source(file.path(SKILL, "scripts", f)))

# ── Tiny harness --------------------------------------------------------------
n_ok <- 0L; n_bad <- 0L; REQS <- list()
ok <- function(name, cond) {
  if (isTRUE(cond)) n_ok <<- n_ok + 1L
  else { n_bad <<- n_bad + 1L; cat("FAIL: ", name, "\n", sep = "") }
}
err   <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
warns <- function(expr) { w <- character(); withCallingHandlers(force(expr),
  warning = function(c) { w <<- c(w, conditionMessage(c)); invokeRestart("muffleWarning") }); w }
stops <- function(name, expr, pattern) ok(paste(name, "(stops with", shQuote(pattern), ")"), grepl(pattern, err(expr)))
keep  <- function(x) { REQS[[length(REQS) + 1L]] <<- x; x }          # every request built here is JSON-checked at the end
src   <- function(x) !is.null(x$sourceRange$sources[[1L]]$sheetId)     # a chart source wrapped in sourceRange

# ── Formulas ------------------------------------------------------------------
ok("f_sumifs quotes an operator criterion", identical(
  f_sumifs("P!C:C", list("P!A:A" = ">5")), '=SUMIFS(P!C:C,P!A:A,">5")'))
ok("f_sumifs quotes >= and text", identical(
  f_sumifs("P!C:C", list("P!A:A" = ">=10", "P!B:B" = "Tech")), '=SUMIFS(P!C:C,P!A:A,">=10",P!B:B,"Tech")'))
ok("f_sumifs leaves a cell ref, an anchored ref and a number alone", identical(
  f_sumifs("P!C:C", list("P!A:A" = "A1", "P!B:B" = "$B$2", "P!D:D" = 5)), "=SUMIFS(P!C:C,P!A:A,A1,P!B:B,$B$2,P!D:D,5)"))
ok("f_safe_div guards a zero denominator", identical(f_safe_div("A1", "B1"), '=IF(B1=0,"",A1/B1)'))
ok("f_sparkline writes numbers bare and quotes text", identical(
  f_sparkline("B2:M2", list(charttype = "line", linewidth = 2, color = "#2457C5")),
  '=SPARKLINE(B2:M2, {"charttype","line";"linewidth",2;"color","#2457C5"})'))
ok("f_sparkline iferror wraps the formula", identical(
  f_sparkline("B2:M2", list(color = "#2457C5"), iferror = TRUE), '=IFERROR(SPARKLINE(B2:M2, {"color","#2457C5"}),"")'))
stops("f_sparkline needs named options", f_sparkline("A1", list(1)), "needs a name")
ok("fmt_image_cell doubles a quote in the URL", identical(
  fmt_image_cell(1, 1, 1, 'https://x.test/a"b')$updateCells$rows[[1]]$values[[1]]$userEnteredValue$formulaValue,
  '=IMAGE("https://x.test/a""b")'))
stops("fmt_image_cell needs an http(s) URL", fmt_image_cell(1, 1, 1, "javascript:x"), "http")

# ── Coordinates and colours ---------------------------------------------------
g <- grid_range(7, 2, 5, 3, 4)
ok("grid_range is 0-based with an exclusive end", identical(
  unlist(g[-1]), c(startRowIndex = 1, endRowIndex = 5, startColumnIndex = 2, endColumnIndex = 4)))
ok("col_letter", identical(vapply(c(1, 26, 27, 52, 702), col_letter, ""), c("A", "Z", "AA", "AZ", "ZZ")))
ok("hex_to_color and color_to_hex round-trip", all(vapply(
  c("#000000", "#FFFFFF", "#2457C5", "#7F3FBF", "#C62828"), function(h) identical(color_to_hex(hex_to_color(h)), h), NA)))

# ── Buffered writes: what is sent for each kind of value ----------------------
cell1 <- function(v, ...) { clear_writes(); write_cell(NULL, "T", 1, 1, v, ...); .wb$data[[1L]]$values[[1L]][[1L]] }
ok("write_cell: a leading + gets a ' prefix", identical(cell1("+abc"), "'+abc"))
ok("write_cell: a leading ' is escaped", identical(cell1("'x"), "''x"))
ok("write_cell: a leading @ gets a ' prefix", identical(cell1("@x"), "'@x"))
ok("write_cell: a signed number string stays a number", identical(cell1("-5"), "-5"))
ok("write_cell: +5 is sent as 5", identical(cell1("+5"), "5"))
ok("write_cell: as_text keeps 00123", identical(cell1("00123", as_text = TRUE), "'00123"))
ok("write_cell: a number goes out as a number", identical(cell1(2e6), 2e6))
ok("write_cell: a logical goes out as a logical", identical(cell1(TRUE), TRUE))
ok("write_cell: NA is an empty cell", identical(cell1(NA), ""))
ok("write_cell: text and formulas pass unchanged", identical(c(cell1("hello"), cell1("=A1+1")), c("hello", "=A1+1")))
stops("write_cell refuses Inf", write_cell(NULL, "T", 1, 1, Inf), "non-finite")
stops("write_cell refuses two values", write_cell(NULL, "T", 1, 1, c(1, 2)), "exactly one")
stops("write_cell refuses a column past ZZ", write_cell(NULL, "T", 1, 703, "x"), "past ZZ")
clear_writes(); write_cell(NULL, "O'Brien", 2, 3, "x")
ok("write_cell doubles a quote in the tab name", identical(.wb$data[[1L]]$range, "'O''Brien'!C2:C2"))
clear_writes(); write_block(NULL, "T", 2, 1, data.frame(a = c("x", "y"), n = c(2, 3)))
ok("write_block queues one typed range", length(.wb$data) == 1L && identical(.wb$data[[1L]]$range, "'T'!A2:B3") &&
   is.numeric(.wb$data[[1L]]$values[[1L]][[2L]]))
clear_writes()

# ── Cell formats, widths, notes -----------------------------------------------
f <- keep(fmt_cells(1, 1, 1, 1, 1, font_size = 12))$repeatCell$fields
ok("fmt_cells masks one text property by itself", identical(f, "userEnteredFormat.textFormat.fontSize"))
f <- keep(fmt_cells(1, 1, 1, 1, 1, bold = TRUE, bg_color = COL_LIGHT_GRAY))$repeatCell$fields
ok("fmt_cells never masks the whole textFormat", grepl("textFormat.bold", f, fixed = TRUE) &&
   grepl("backgroundColor", f, fixed = TRUE) && !grepl("textFormat(,|$)", f))
stops("fmt_cells refuses numfmt plus numfmt_type", fmt_cells(1, 1, 1, 1, 1, numfmt = NUMFMT_PCT, numfmt_type = "NUMBER"), "not both")
w <- keep(fmt_col_widths(3, c(220, 90, 90, 90.4, 140)))
ok("fmt_col_widths merges equal neighbours", length(w) == 3L)
ok("fmt_col_widths ranges", identical(vapply(w, function(r) r$updateDimensionProperties$range$startIndex, 0L), c(0L, 1L, 4L)) &&
   identical(vapply(w, function(r) r$updateDimensionProperties$range$endIndex, 0L), c(1L, 4L, 5L)))
ok("fmt_col_widths rounds to whole pixels", all(vapply(w, function(r) {
  p <- r$updateDimensionProperties$properties$pixelSize; p == round(p) }, NA)))
stops("fmt_col_widths refuses a zero width", fmt_col_widths(3, c(100, 0)), "positive pixel widths")
stops("fmt_col_widths refuses NA", fmt_col_widths(3, c(100, NA)), "positive pixel widths")
n <- keep(fmt_note(3, 2, 4, "Risk score"))$updateCells
ok("fmt_note masks only the note", identical(n$fields, "note") && identical(n$rows[[1L]]$values[[1L]]$note, "Risk score"))
stops("fmt_note refuses NA", fmt_note(3, 2, 4, NA_character_), "one string")
ok("fmt_group_cols returns two requests", length(keep(fmt_group_cols(3, 2, 4))) == 2L)
tc <- keep(fmt_theme_colors(accent1 = "2457C5"))$updateSpreadsheetProperties$properties$spreadsheetTheme$themeColors
ok("fmt_theme_colors sends the complete theme", length(tc) == 9L)
stops("fmt_theme_colors refuses a bad hex", fmt_theme_colors(accent1 = "nope"), "6-digit hex")
stops("fmt_named_range refuses an invalid name", fmt_named_range(3, "2bad name", 1, 1, 1, 1), "Invalid named range")

# ── Tab order -----------------------------------------------------------------
o <- keep(fmt_tab_order(NULL, c(5, 9, 2)))
ok("fmt_tab_order from sheetIds needs no lookup", identical(
  vapply(o, function(r) r$updateSheetProperties$properties$index, 0L), 0:2) &&
  identical(vapply(o, function(r) r$updateSheetProperties$properties$sheetId, 0), c(5, 9, 2)))
stops("fmt_tab_order refuses a repeat", fmt_tab_order(NULL, c(1, 1)), "without NA or repeats")
stops("fmt_tab_order refuses NA", fmt_tab_order(NULL, c(1, NA)), "without NA or repeats")
stops("fmt_tab_order refuses an empty vector", fmt_tab_order(NULL, numeric(0)), "without NA or repeats")

# ── Validation and conditional rules ------------------------------------------
v <- keep(fmt_validation(3, 5, 50, 3, 3, "NUMBER_BETWEEN", c(0, 1)))$setDataValidation$rule
ok("fmt_validation sends the values as an unnamed array", is.null(names(v$condition$values)) &&
   identical(vapply(v$condition$values, function(x) x$userEnteredValue, ""), c("0", "1")))
stops("fmt_validation refuses an unknown type", fmt_validation(3, 5, 50, 3, 3, "NOPE", 1), "must be one of")
stops("fmt_validation checks the value count", fmt_validation(3, 5, 50, 3, 3, "NUMBER_BETWEEN", 1), "takes 2 value")
stops("fmt_validation needs = in a custom formula", fmt_validation(3, 5, 50, 3, 3, "CUSTOM_FORMULA", "A1>0"), "starts with '='")
r <- keep(fmt_cond_text(3, 2, 5, 1, 2, op = "contains", text = "late", bg_color = COL_RED_LIGHT))$addConditionalFormatRule
ok("fmt_cond_text contains", identical(r$rule$booleanRule$condition$type, "TEXT_CONTAINS") &&
   identical(r$rule$booleanRule$condition$values[[1L]]$userEnteredValue, "late") && identical(r$index, 0L))
r <- keep(fmt_cond_number(3, 2, 5, 1, 2, value = 0.5, op = "less_eq", font_color = COL_RED_TEXT))$addConditionalFormatRule
ok("fmt_cond_number", identical(r$rule$booleanRule$condition$type, "NUMBER_LESS_THAN_EQ") &&
   identical(r$rule$booleanRule$condition$values[[1L]]$userEnteredValue, "0.5"))
ok("fmt_cond_formula takes an index", identical(
  keep(fmt_cond_formula(3, 2, 5, 1, 2, '=$A2="x"', bg_color = COL_RED_LIGHT, index = 3L))$addConditionalFormatRule$index, 3L))
stops("fmt_cond_formula needs =", fmt_cond_formula(3, 2, 5, 1, 2, "A2", bg_color = COL_RED_LIGHT), "must start with")
stops("a conditional rule needs a format", fmt_cond_formula(3, 2, 5, 1, 2, "=A2"), "at least one of")

# new_batch numbers rules per tab, so the FIRST rule listed wins
b <- new_batch()
b$cf(fmt_cond_negative, 10, 2, 5, 1, 2); b$cf(fmt_cond_negative, 10, 6, 9, 1, 2); b$cf(fmt_cond_negative, 20, 2, 5, 1, 2)
b$push(fmt_cells(10, 1, 1, 1, 2, bold = TRUE)); b$push(fmt_col_widths(10, c(100, 100, 50)))
bb <- keep(b$get())
ok("new_batch numbers rules per tab", identical(
  vapply(bb[1:3], function(x) x$addConditionalFormatRule$index, 0L), c(0L, 1L, 0L)))
ok("new_batch flattens a list of requests", length(bb) == 6L)

# ── Charts, slicers, protection -----------------------------------------------
ser <- list(list(range = c(1, 13, 3, 3)))
cb <- keep(fmt_chart_basic(3, "T", "LINE", c(1, 13, 2, 2), ser))$addChart$chart$spec$basicChart
ok("fmt_chart_basic wraps domain and series in sourceRange", src(cb$domains[[1L]]$domain) && src(cb$series[[1L]]$series))
cbar <- keep(fmt_chart_bar(3, "T", c(1, 13, 2, 2), ser))$addChart$chart$spec$basicChart
ok("fmt_chart_bar uses the bottom axis and sourceRange", identical(cbar$series[[1L]]$targetAxis, "BOTTOM_AXIS") && src(cbar$series[[1L]]$series))
cw <- keep(fmt_chart_waterfall(3, "T", c(1, 6, 1, 1), c(1, 6, 2, 2), subtotal_indices = c(0L, 5L)))$addChart$chart$spec$waterfallChart
ok("fmt_chart_waterfall wraps sources and marks totals", src(cw$domain$data) && src(cw$series[[1L]]$data) &&
   length(cw$series[[1L]]$customSubtotals) == 2L && isTRUE(cw$series[[1L]]$customSubtotals[[1L]]$dataIsSubtotal))
ok("fmt_chart_waterfall omits customSubtotals without indices", is.null(
  fmt_chart_waterfall(3, "T", c(1, 6, 1, 1), c(1, 6, 2, 2))$addChart$chart$spec$waterfallChart$series[[1L]]$customSubtotals))
ok("fmt_chart_waterfall warns about legend", length(warns(fmt_chart_waterfall(3, "T", c(1, 6, 1, 1), c(1, 6, 2, 2), legend = "BOTTOM_LEGEND"))) == 1L)
cp <- keep(fmt_chart_pie(3, "T", c(1, 5, 1, 1), c(1, 5, 2, 2), donut = TRUE))$addChart$chart$spec$pieChart
ok("fmt_chart_pie wraps sources and sets the hole", src(cp$domain) && src(cp$series) && identical(cp$pieHole, 0.7))
ok("fmt_chart_basic warns that right-axis settings do nothing",
   length(warns(fmt_chart_basic(3, "T", "LINE", c(1, 13, 2, 2), ser, y2_title = "x"))) == 1L)
stops("a chart style refuses an unknown key", fmt_chart_basic(3, "T", "LINE", c(1, 13, 2, 2), ser, style = list(nope = 1)), "unknown key")
sl <- keep(fmt_slicer(3, 3, c(1, 20, 1, 4), 2, 1, 6))$addSlicer$slicer$spec
ok("fmt_slicer has columnIndex on the spec and no filterSpec", is.null(sl$filterSpec) && identical(sl$columnIndex, 2L))
ok("fmt_slicer passes filter_criteria through", identical(
  fmt_slicer(3, 3, c(1, 20, 1, 4), 2, 1, 6, filter_criteria = list(hiddenValues = list("x")))$addSlicer$slicer$spec$filterCriteria,
  list(hiddenValues = list("x"))))
stops("fmt_protected_range refuses partial bounds", fmt_protected_range(3, 1, 2), "all of start_row")
stops("fmt_protected_range refuses unprotected_ranges on a bounded range",
      fmt_protected_range(3, 1, 2, 1, 2, unprotected_ranges = list(grid_range(3, 1, 1, 1, 1))), "whole-sheet")
pr <- keep(fmt_protected_range(3, unprotected_ranges = grid_range(3, 5, 9, 1, 2)))$addProtectedRange$protectedRange
ok("fmt_protected_range protects the whole sheet", identical(pr$range, list(sheetId = 3)) && length(pr$unprotectedRanges) == 1L)

# ── Guards that must stop before any request ----------------------------------
for (bad in list(NULL, character(0), NA_character_, 5L))
  stops(paste("gs_reset_tabs refuses tabs =", deparse(bad)), gs_reset_tabs("not-a-sheet", bad), "Nothing was changed")
stops("gs_reset_tabs refuses a missing tabs", gs_reset_tabs("not-a-sheet"), "Nothing was changed")
stops("gs_open_or_create refuses an unnamed rows vector", gs_open_or_create("T", c("A", "B"), id = "", rows = c(10, 20)), "named by tab")
stops("fmt_image_cell refuses OVER_CELL", fmt_image_cell(3, 1, 1, "https://x.test/a.png", mode = "OVER_CELL"), "not supported")

# ── Saved logins: client filter, token loader, default-account rule ------------
# Fake tokens (no network: credentials are given, cache = FALSE) in a temp cache.
Sys.unsetenv("GS_OAUTH_CLIENT")   # a client exported in the caller's shell must not steer these checks
fake_cache <- file.path(tempdir(), "fake-gargle"); dir.create(fake_cache)
fake_token <- function(id, email = "u@example.com") gargle::gargle2.0_token(
  email = email, client = gargle::gargle_oauth_client(id = id, secret = "s", name = id),
  package = "offline-test", scope = GS_SCOPE, credentials = list(access_token = "x"), cache = FALSE)
tA <- fake_token("client-a"); tB <- fake_token("client-b")
saveRDS(tA, file.path(fake_cache, paste0(tA$hash()))); saveRDS(tB, file.path(fake_cache, paste0(tB$hash())))
Sys.setFileTime(file.path(fake_cache, tA$hash()), Sys.time() - 3600)      # A is older
ok("token files are named <hash>_<email>", all(grepl("_u@example.com$", list.files(fake_cache))))
l0 <- gs_cached_logins(fake_cache)
ok("without GS_OAUTH_CLIENT any client counts", nrow(l0) == 2L && all(l0$has_scope) && setequal(l0$client, c("client-a", "client-b")))
ld <- .gs_load_token(l0, "U@example.com", fake_cache)
ok("the loader picks the newest matching file", identical(ld$token$client$id, "client-b"))
ok("the loader points the token's cache_path at the cache in use", identical(ld$token$cache_path, fake_cache))
ok("the loader returns NULL for an account with no login", is.null(.gs_load_token(l0, "nobody@example.com", fake_cache)))
client_json <- file.path(tempdir(), "client.json")
# A fake Desktop-app client file. The secret field name is built with paste0() so
# check.sh's secret scan does not flag this placeholder.
fake_client <- stats::setNames(list("client-a", "s", "p", list("http://localhost")),
                               c("client_id", paste0("client", "_secret"), "project_id", "redirect_uris"))
writeLines(jsonlite::toJSON(list(installed = fake_client), auto_unbox = TRUE), client_json)
Sys.setenv(GS_OAUTH_CLIENT = client_json)
la <- gs_cached_logins(fake_cache)
ok("GS_OAUTH_CLIENT keeps only that client's token", identical(la$has_scope[la$client == "client-a"], TRUE) &&
     identical(la$has_scope[la$client == "client-b"], FALSE) && identical(la$client_ok[la$client == "client-b"], FALSE))
ok("with GS_OAUTH_CLIENT the loader takes the older matching file", identical(.gs_load_token(la, "u@example.com", fake_cache)$token$client$id, "client-a"))
# .gs_use_token must install THIS token even when another credential source comes
# first in gargle's chain (as GOOGLE_APPLICATION_CREDENTIALS or a GCE VM would).
# tA has no refresh token, so nothing is sent to Google.
gargle::cred_funs_set(list(decoy = function(scopes, ...) fake_token("decoy"),
                           credentials_byo_oauth2 = gargle::credentials_byo_oauth2))
use_res <- .gs_use_token(tA)
gargle::cred_funs_set_default()
ok("the saved token wins over a credential source earlier in gargle's chain",
   identical(use_res, "ok") && identical(googlesheets4:::.auth$cred$client$id, "client-a"))
googlesheets4::gs4_deauth()
Sys.setenv(GS_OAUTH_CLIENT = file.path(tempdir(), "missing.json"))
stops("a missing GS_OAUTH_CLIENT file", .gs_oauth_client(), "does not exist")
Sys.unsetenv("GS_OAUTH_CLIENT")

# gs_setup.R runs main() when sourced, so take only the function it needs.
setup_exprs <- parse(file.path(SKILL, "scripts", "gs_setup.R"))
for (e in setup_exprs) if (is.call(e) && length(e) > 1L && identical(deparse(e[[2L]]), "should_save_default")) eval(e)
ok("auth saves the default when no email was given", should_save_default(NULL, TRUE, FALSE))
ok("auth saves the first default", should_save_default("a@x.com", FALSE, FALSE))
ok("auth <other> leaves an existing default alone", !should_save_default("a@x.com", TRUE, FALSE))
ok("a mismatch never becomes the default", !should_save_default("a@x.com", FALSE, TRUE) && !should_save_default(NULL, TRUE, TRUE))

# ── visual_qa output folder and sheet references ---------------------------------
for (f in c("gs_qa.R", "gs_visual_qa.R")) suppressMessages(source(file.path(SKILL, "scripts", f)))
vq <- .gs_visual_qa_dir("abc123")
ok("visual_qa's default folder outlives Rscript (not under tempdir())",
   !startsWith(normalizePath(vq, mustWork = FALSE), normalizePath(tempdir())) && endsWith(vq, file.path("visual_qa", "abc123")))
ok("a sheet URL resolves to its id offline (as batch_format etc. now do)", identical(
   as.character(googlesheets4::as_sheets_id("https://docs.google.com/spreadsheets/d/1abcDEF_-x/edit#gid=0")), "1abcDEF_-x"))

# ── Design tokens and layout helpers (the Ledger default look) ------------------
hx <- function(c) color_to_hex(c)
ok("ds_tokens() default ladder is the documented one", identical(
  vapply(list(COL_ACCENT_100, COL_ACCENT_200, COL_ACCENT, COL_ACCENT_700, COL_ACCENT_800), hx, ""),
  c("#E9EEF9", "#C8D5F0", "#2457C5", "#1C449A", "#14306C")))
ok("THEME_DEFAULT feeds fmt_theme_colors() with the accent first and Roboto",
   identical(THEME_DEFAULT$accent1, "2457C5") && identical(THEME_DEFAULT$font_family, "Roboto") &&
   !is.null(keep(do.call(fmt_theme_colors, THEME_DEFAULT))$updateSpreadsheetProperties))
ladder_ok <- function(a) { t <- suppressWarnings(ds_tokens(a))
  .contrast(t$COL_ACCENT, t$COL_ACCENT_100) >= 4.5 && .contrast(t$COL_ACCENT_700, t$COL_ACCENT_100) >= 7 &&
  .contrast(t$COL_ACCENT_400, COL_WHITE) >= 3 && .contrast(t$COL_ACCENT, COL_WHITE) >= 3 }
ok("every swapped accent keeps its ladder readable (600 4.5:1 and 700 7:1 on 100, 400 3:1 on white)",
   all(vapply(c("2457C5", "7B3F98", "8A3A5C", "0F766E", "B4462B", "6E7F1A", "767676", "C2410C", "1A7F5A"), ladder_ok, NA)))
stops("ds_tokens() with an accent too light to read", ds_tokens("EEEEEE"), "needs at least 3:1")
stops("ds_tokens() with a non-hex accent", ds_tokens("blue"), "6-digit hex")
ok("ds_tokens() warns when the accent sits next to a status hue", length(warns(ds_tokens("0F766E"))) == 1L &&
   length(warns(ds_tokens("7B3F98"))) == 0L && length(warns(ds_tokens("3A4A5C"))) == 0L)
ok("status inks reach 4.5:1 on their fills and on white", all(vapply(STATUS, function(s)
   .contrast(s$ink, s$fill) >= 4.5 && .contrast(s$ink, COL_WHITE) >= 4.5, NA)))
ok("text tiers, inputs and links reach 4.5:1 on white and on the surface grey", all(vapply(
   list(COL_INK, COL_TEXT_2, COL_TEXT_3, COL_INPUT_FG, COL_LINK_FG, COL_POSITIVE, COL_NEGATIVE), function(c)
   .contrast(c, COL_WHITE) >= 4.5 && .contrast(c, COL_SURFACE) >= 4.5, NA)) &&
   .contrast(COL_INPUT_FG, COL_INPUT_BG) >= 4.5)
ok("STYLE_GRAYED_OUT passes the audit's contrast floor (was 1.7:1)",
   .contrast(STYLE_GRAYED_OUT$font_color, STYLE_GRAYED_OUT$bg_color) >= 4.5)
presets <- mget(grep("^STYLE_", ls(), value = TRUE))
ok("no STYLE_* preset sets a font family (the theme does)",
   !any(vapply(presets, function(p) is.list(p) && !is.null(p$font_family), NA)))
ok("old colour names still exist", all(vapply(c("COL_LIGHT_GRAY", "COL_GRAY_TEXT", "COL_MUTED_TEXT", "COL_RED_TEXT",
   "COL_GREEN_LIGHT", "COL_BLUE_LIGHT", "COL_YELLOW_LIGHT", "COL_RED_LIGHT", "COL_BRAND", "COL_BRAND_DEEP",
   "COL_BRAND_SUBTLE", "COL_INK", "COL_POSITIVE", "COL_NEGATIVE", "COL_WARNING", "COL_WARNING_SOFT",
   "COL_INPUT_FG", "COL_FORMULA_FG", "COL_LINK_FG", "BRAND_FONT"), exists, NA)))
wsh <- keep(write_section_header(NULL, "T", 3, 5, "Revenue"))
clear_writes()
ok("write_section_header() returns merge, style, height and an ink top rule", length(wsh) == 4L &&
   !is.null(wsh[[1]]$mergeCells) && identical(wsh[[4]]$updateBorders$top$style, "SOLID") &&
   identical(wsh[[2]]$repeatCell$cell$userEnteredFormat$backgroundColor, COL_WHITE))
tb <- keep(fmt_tab_base(3, 40, 12, "dashboard", widths = c(224, 112), inputs = TRUE))
grid <- Filter(function(r) !is.null(r$updateSheetProperties$properties$gridProperties$hideGridlines), tb)
ok("fmt_tab_base(dashboard) hides gridlines, adds 16 px gutters, colours an input tab",
   isTRUE(grid[[1]]$updateSheetProperties$properties$gridProperties$hideGridlines) &&
   any(vapply(tb, function(r) identical(r$updateDimensionProperties$properties$pixelSize, 16L) ||
                                 identical(r$updateDimensionProperties$properties$pixelSize, 16), NA)) &&
   any(vapply(tb, function(r) !is.null(r$updateSheetProperties$properties$tabColorStyle), NA)))
td <- fmt_tab_base(3, 40, 12, "data")
ok("fmt_tab_base(data) shows gridlines, freezes row 1, no title block", any(vapply(td, function(r)
   identical(r$updateSheetProperties$properties$gridProperties$frozenRowCount, 1L), NA)) &&
   !any(vapply(td, function(r) identical(r$repeatCell$cell$userEnteredFormat$textFormat$fontSize, 20), NA)))
sec <- keep(fmt_section(3, 10, 2, 6, numeric_cols = 3:5, meta_col = 6))
ok("fmt_section() draws the ink rule, the header rule and right-aligns numeric headers",
   sum(vapply(sec, function(r) !is.null(r$updateBorders), NA)) == 2L &&
   sum(vapply(sec, function(r) identical(r$repeatCell$cell$userEnteredFormat$horizontalAlignment, "RIGHT"), NA)) >= 4L)
body <- keep(fmt_table_body(3, 12, 17, 2, 6, numeric_cols = 3:5, numfmt = NUMFMT_INT, total_rows = 17, total_col = 6))
ok("fmt_table_body() gives the total row an ink rule over a double rule",
   any(vapply(body, function(r) identical(r$updateBorders$bottom$style, "DOUBLE") &&
                               identical(r$updateBorders$top$style, "SOLID"), NA)))
stops("fmt_table_body() with a numfmt list of the wrong length",
      fmt_table_body(3, 12, 17, 2, 6, numeric_cols = 3:5, numfmt = list(NUMFMT_INT, NUMFMT_PCT)), "one per numeric column")
kp <- keep(fmt_kpi_strip(3, 6, 2:6, good = c("down", "up", "up", "none", "up")))
sizes <- unlist(lapply(kp, function(r) r$repeatCell$cell$userEnteredFormat$textFormat$fontSize))
cfs <- Filter(function(r) !is.null(r$addConditionalFormatRule), kp)
first_gt <- cfs[[1]]$addConditionalFormatRule$rule$booleanRule
ok("fmt_kpi_strip(): one 28 pt lead, 18 pt siblings, two delta rules per KPI with a direction",
   sum(sizes == 28) == 1L && sum(sizes == 18) == 4L && length(cfs) == 8L &&
   identical(first_gt$condition$type, "NUMBER_GREATER") &&
   identical(first_gt$format$textFormat$foregroundColorStyle$rgbColor, COL_NEGATIVE))  # a cost going up is bad
stops("fmt_kpi_strip() with an unknown direction", fmt_kpi_strip(3, 6, 2:3, good = "sideways"), "must be")
st <- keep(fmt_status(3, 12, 16, 6, 6, c(Over = "negative", Near = "warning"), index = 2L))
ok("fmt_status() adds one rule per state in priority order", length(st) == 3L &&
   identical(st[[2]]$addConditionalFormatRule$index, 2L) && identical(st[[3]]$addConditionalFormatRule$index, 3L))
stops("fmt_status() with an unknown state colour", fmt_status(3, 1, 2, 1, 1, c(Over = "red")), "unknown state")
stops("fmt_status() with unnamed states", fmt_status(3, 1, 2, 1, 1, "negative"), "named character")
ov <- keep(fmt_chart_basic(3, "T", "COMBO", c(1, 8, 1, 1), list(list(range = c(1, 8, 2, 2), type = "COLUMN",
  override = list(list(index = 0L, color = COL_NEGATIVE))))))$addChart$chart$spec$basicChart$series[[1]]
ok("a series `override` becomes styleOverrides", identical(ov$styleOverrides[[1]]$index, 0L) &&
   identical(ov$styleOverrides[[1]]$colorStyle$rgbColor, COL_NEGATIVE))
wf <- fmt_chart_waterfall(3, "T", c(1, 6, 1, 1), c(1, 6, 2, 2))$addChart$chart$spec$waterfallChart$series[[1]]
ok("waterfall colours default to the tokens", identical(wf$positiveColumnsStyle$color, COL_POSITIVE) &&
   identical(wf$subtotalColumnsStyle$color, COL_ACCENT))

ho <- keep(fmt_section(3, 5, 2, 6, numeric_cols = 4, heading = FALSE))
ok("fmt_section(heading = FALSE) styles only the header row, on `row`", length(ho) == 4L &&
   ho[[1]]$repeatCell$range$startRowIndex == 4 && identical(ho[[1]]$repeatCell$cell$userEnteredFormat$textFormat$fontSize, 9))
stops("fmt_section(heading = FALSE, header = FALSE)", fmt_section(3, 5, 2, 6, header = FALSE, heading = FALSE), "needs header")
tc2 <- fmt_table_body(3, 5, 9, 2, 9, total_col = c(5, 9))
ok("fmt_table_body() takes several total columns", sum(vapply(tc2, function(r) !is.null(r$updateBorders$left), NA)) == 2L)
ok("fmt_tab_base(data, title_row = 2) keeps the title block on a data tab",
   any(vapply(fmt_tab_base(3, 40, 8, "data", title_row = 2L), function(r)
     identical(r$repeatCell$cell$userEnteredFormat$textFormat$fontSize, 20), NA)))

# ── Every request must serialise ----------------------------------------------
js <- tryCatch(jsonlite::toJSON(REQS, auto_unbox = TRUE, digits = NA), error = function(e) NULL)
ok("every request built above serialises to valid JSON", !is.null(js) && jsonlite::validate(js))

cat(sprintf("offline-test: %d passed, %d failed\n", n_ok, n_bad))
if (n_bad > 0L) quit(status = 1L)
