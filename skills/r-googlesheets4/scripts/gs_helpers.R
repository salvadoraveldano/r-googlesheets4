# =============================================================================
# gs_helpers.R — Core formatting + I/O helpers for googlesheets4
# =============================================================================
#
# Battle-tested wrappers around the Sheets API v4 `batchUpdate` endpoint plus
# coordinate / color utilities. All `fmt_*` functions return a single request
# object (a list) ready to slot into a `batch_format()` call — except
# `fmt_group_cols()` and `fmt_group_rows()`, which return TWO requests (see
# their headers). Use `c()` not `list()` when combining those.
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
#' clobbers other formatting on the same range.
fmt_cells <- function(sheet_id, start_row, end_row, start_col, end_col,
                      font_family = NULL, font_size = NULL, bold = NULL,
                      italic = NULL, underline = NULL,
                      font_color = NULL, bg_color = NULL,
                      numfmt_type = NULL, numfmt_pattern = NULL,
                      halign = NULL, valign = NULL, wrap = NULL) {

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
    fields <- c(fields, "userEnteredFormat.textFormat")
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

# ── Dimensions: width / height ---------------------------------------------

fmt_col_width <- function(sheet_id, start_col, end_col, width_px) {
  list(updateDimensionProperties = list(
    range = list(sheetId = sheet_id, dimension = "COLUMNS",
                 startIndex = start_col - 1L, endIndex = end_col),
    properties = list(pixelSize = width_px),
    fields = "pixelSize"
  ))
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

fmt_dropdown <- function(sheet_id, start_row, end_row, start_col, end_col, values) {
  list(setDataValidation = list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    rule = list(
      condition = list(
        type = "ONE_OF_LIST",
        values = lapply(values, function(v) list(userEnteredValue = as.character(v)))
      ),
      showCustomUi = TRUE,
      strict = TRUE
    )
  ))
}

fmt_dropdown_range <- function(sheet_id, start_row, end_row, start_col, end_col,
                               source_range) {
  # source_range is an A1-style ref like "=Lists!B2:B13"
  list(setDataValidation = list(
    range = grid_range(sheet_id, start_row, end_row, start_col, end_col),
    rule = list(
      condition = list(
        type = "ONE_OF_RANGE",
        values = list(list(userEnteredValue = source_range))
      ),
      showCustomUi = TRUE,
      strict = TRUE
    )
  ))
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
                              color = COL_RED_TEXT) {
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
    index = 0L
  ))
}

fmt_cond_color_scale <- function(sheet_id, start_row, end_row, start_col, end_col,
                                 min_color = COL_GREEN_LIGHT,
                                 mid_color = COL_YELLOW_LIGHT,
                                 max_color = COL_RED_LIGHT) {
  list(addConditionalFormatRule = list(
    rule = list(
      ranges = list(grid_range(sheet_id, start_row, end_row, start_col, end_col)),
      gradientRule = list(
        minpoint = list(color = min_color, type = "MIN"),
        midpoint = list(color = mid_color, type = "PERCENTILE", value = "50"),
        maxpoint = list(color = max_color, type = "MAX")
      )
    ),
    index = 0L
  ))
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
#' ⚠ Ordering: `fmt_cells()` with ANY textFormat arg sends the field mask
#' `userEnteredFormat.textFormat` — the WHOLE object — which wipes the link.
#' Apply link requests in a SEPARATE batch AFTER all formatting batches.
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
#' @param requests  list of request objects (each from an `fmt_*` helper)
#' @param strict    if TRUE, `stop()` on HTTP ≥ 400 instead of only logging
#' @return invisible httr response
batch_format <- function(ss, requests, strict = FALSE) {
  if (length(requests) == 0L) return(invisible(NULL))
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
#' `tabs` is a character vector of tab names; missing tabs are added on reuse.
#' Prints the id so it can be passed back as SHEET_ID=<id> on the next run.
gs_open_or_create <- function(title, tabs, id = Sys.getenv("SHEET_ID", "")) {
  if (!nzchar(id)) {
    ss <- googlesheets4::gs4_create(title, sheets = tabs, timeZone = Sys.timezone())
    message("[gs_open_or_create] created ", as.character(ss), "  (rebuild with SHEET_ID=", as.character(ss), ")")
    return(ss)
  }
  ss <- googlesheets4::as_sheets_id(id)
  have <- googlesheets4::sheet_names(ss)
  for (t in setdiff(tabs, have)) googlesheets4::sheet_add(ss, sheet = t)
  message("[gs_open_or_create] reusing ", id)
  ss
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
