# Formatting via Sheets API v4 batchUpdate

The workhorse reference. Every cell-level format goes through `batchUpdate`.
The helpers in `scripts/gs_helpers.R` wrap each request type — this doc
explains the request shapes and when to use which.

## The pattern

```r
# 1. Build a list of request objects
requests <- list(
  list(repeatCell    = list(...)),
  list(mergeCells    = list(...)),
  list(updateBorders = list(...))
)

# 2. Send via batch_format() (handles HTTP-status check)
batch_format(ss, requests)
```

Each `fmt_*` helper returns one request — drop them into the `requests`
list. **Two helpers return TWO requests** (`fmt_group_cols`, `fmt_group_rows`)
and `fmt_tab_order` returns one per tab — combine those with `c()`, not
`list()`. See the warning below.

## Grid coordinates are 0-based

Sheets API: row 1 = `startRowIndex 0`, end indices are exclusive. Always
use `grid_range()` from `gs_helpers.R`, which takes 1-based input and
produces the API shape:

```r
grid_range(sheet_id = 0L, start_row = 1L, end_row = 1L, start_col = 1L, end_col = 6L)
# → list(sheetId = 0, startRowIndex = 0, endRowIndex = 1,
#         startColumnIndex = 0, endColumnIndex = 6)
# (row 1, columns A:F on the first sheet)
```

## Colors are 0-1 float RGB, not hex

Sheets API rejects hex strings. Convert via `hex_to_color()`:

```r
COL_BRAND <- hex_to_color("2457C5")   # brand blue
# → list(red = 0.141, green = 0.341, blue = 0.773)
```

`gs_helpers.R` ships generic constants (`COL_BLACK`, `COL_WHITE`,
`COL_GRAY_TEXT`, …); brand colors live in `brand.R`.

## Request types and when to use which

### `repeatCell` → `fmt_cells()`

The most common request — applies font, fill, number format, and
alignment to a range. Set only the fields you want; the resulting
`fields` mask reflects exactly what you specified, so it doesn't clobber
unrelated formatting.

```r
fmt_cells(sheet_id = 0L, start_row = 1L, end_row = 1L, start_col = 1L, end_col = 6L,
          font_family = "Arial", font_size = 12, bold = TRUE,
          font_color = COL_WHITE, bg_color = COL_BRAND,
          halign = "CENTER", valign = "MIDDLE")
```

Parameters: `font_family`, `font_size`, `bold`, `italic`, `underline`,
`font_color`, `bg_color`, `numfmt_type`, `numfmt_pattern`, `halign`,
`valign`, `wrap`, `numfmt`.

Number format two ways: `numfmt_type` + `numfmt_pattern`, or `numfmt = list(type =
, pattern = )`, which takes the `NUMFMT_*` constants (`NUMFMT_CURRENCY`,
`NUMFMT_PCT`, `NUMFMT_INT`, ...) and your own formats. Giving both is an error.

```r
fmt_cells(sid, 5, 20, 3, 3, numfmt = NUMFMT_CURRENCY)                       # $1,235
fmt_cells(sid, 5, 20, 4, 4, numfmt = list(type = "NUMBER", pattern = '0.0"x"'))  # 2.5x
```

A small local alias is enough when one build repeats a format:
`NF <- function(p, type = "NUMBER") list(type = type, pattern = p)`.

`halign` ∈ `LEFT` / `CENTER` / `RIGHT`. `valign` ∈ `TOP` / `MIDDLE` /
`BOTTOM`. `wrap = TRUE` = WRAP, `wrap = FALSE` = OVERFLOW_CELL.
**`OVERFLOW_OR_ELLIPSIS` is not a valid value** — Sheets API rejects it.

### `mergeCells` → `fmt_merge()`

```r
fmt_merge(sheet_id, start_row, end_row, start_col, end_col,
          merge_type = "MERGE_ALL")
# merge_type ∈ MERGE_ALL | MERGE_COLUMNS | MERGE_ROWS
```

Format the **full merged range**, not just the top-left cell.

### `updateBorders` → `fmt_borders()`

```r
fmt_borders(sid, 25, 25, 1, 6,
            top    = list(style = "DOUBLE", color = COL_BRAND),
            bottom = list(style = "DOUBLE", color = COL_BRAND))
```

Border styles: `SOLID` / `SOLID_MEDIUM` / `SOLID_THICK` / `DOUBLE` /
`DASHED` / `DOTTED` / `NONE`.

⚠️ **Last writer wins for shared edges.** A row-wide bottom border on
row 7 and a column-wide top border on row 8 are the same edge — whichever
runs later in the batch wins. To preserve emphasis borders, apply them
in a final reassertion batch after all other styling.

### `updateSheetProperties` → `fmt_gridlines()` / `fmt_freeze()` / `fmt_tab_color()` / `fmt_tab_order()`

```r
fmt_gridlines(sid, show = FALSE)
fmt_freeze(sid, rows = 1L, cols = 0L)
fmt_tab_color(sid, COL_BRAND)
fmt_tab_order(ss, c("Cover", "Data", "Forecast"))   # one request per tab: use c()
```

`fmt_tab_order()` sets the tab order from a vector of names (or of sheetIds with
`fmt_tab_order(NULL, ids)`); see [creating-and-tabs.md](creating-and-tabs.md).

⚠️ **Freeze + merge conflict.** You cannot freeze cols that contain part
of a merged cell. If you get HTTP 400 *"can't freeze columns which contain
only part of a merged cell"*, either drop the boundary-crossing merge,
merge only the non-frozen portion, or freeze rows only.

### `updateDimensionProperties` → `fmt_col_width()` / `fmt_col_widths()` / `fmt_row_height()`

```r
fmt_col_width(sid, start_col = 1L, end_col = 1L, width_px = 280L)
fmt_row_height(sid, start_row = 5L, end_row = 5L, height_px = 30L)

# Widths for a run of columns in one call: column start_col + i - 1 gets widths[i]
fmt_col_widths(sid, c(220, 90, 90, 90, 140))                # A:E, three requests (equal runs merge)
fmt_col_widths(sid, c(120, 75.6, 200), start_col = 7)       # G:I; 75.6 is sent as 76
```

`fmt_col_widths()` returns a LIST of requests, so combine it with `c()`, not
`list()`. It rounds each width to whole pixels because the API answers HTTP 400
to a fraction (`fmt_col_width()` passes the number through, so round it
yourself there). A width that is empty, `NA`, `Inf`, zero or negative stops
before any request is built.

### `addDimensionGroup` → `fmt_group_cols()` / `fmt_group_rows()`

⚠️ **These return TWO requests** (the group + the hide). Use `c()` to
flatten into the parent list:

```r
# WRONG: list() wraps the 2 requests in another list → invalid batchUpdate
all_fmt <- list(fmt_gridlines(sid),
                fmt_group_cols(sid, 21, 26))   # ← bug

# CORRECT: c() flattens
all_fmt <- c(list(fmt_gridlines(sid)),
             fmt_group_cols(sid, 21, 26))
batch_format(ss, all_fmt)
```

The same applies to `fmt_group_rows()`.

### `setDataValidation` → `fmt_dropdown()` / `fmt_dropdown_range()` / `fmt_validation()`

Dropdowns, plus number / date / text / custom-formula rules. Remember that API
writes bypass validation. See [data-validation.md](data-validation.md).

### `addNamedRange` → `fmt_named_range()`

See [named-ranges.md](named-ranges.md).

### `addConditionalFormatRule` → `fmt_cond_negative()` / `fmt_cond_color_scale()` / `fmt_cond_formula()` / `fmt_cond_text()` / `fmt_cond_number()`

See [conditional-formatting.md](conditional-formatting.md).

### `updateSpreadsheetProperties` → `fmt_theme_colors()`

The spreadsheet THEME holds the accent palette. Pie and doughnut slices take
ACCENT1, ACCENT2, ... in order, and a slice cannot be coloured individually, so
the theme is how you choose them.

```r
batch_format(ss, list(fmt_theme_colors(
  accent1 = "2457C5", accent2 = "1F9D8B", accent3 = "F2A33A",
  accent4 = "7A4FB3", accent5 = "5BA8E0", accent6 = "5B6B8C",
  font_family = "Arial")), strict = TRUE)
```

Send it before or after the charts: a chart takes its colours from the theme
when it renders (checked live: an existing pie re-coloured when the theme
changed). Also checked live: the colours and font read back from
`spreadsheets.get` (`properties.spreadsheetTheme`), and a pie chart rendered in
the new accents in an exported PDF.

⚠ The API only accepts a COMPLETE theme: all nine colours and a font. So every
colour you leave out goes back to Google's default theme (`accent1` 4285F4,
`accent2` EA4335, `accent3` FBBC04, `accent4` 34A853, `accent5` FF6D01,
`accent6` 46BDC6, `text` 000000, `background` FFFFFF, `link` 1155CC; checked
against a new sheet) and `font_family` (default "Arial") replaces the theme
font. `text`, `background` and `link` are optional arguments. Each colour is a
hex string or an `hex_to_color()` list. Cells with their own colours are not
touched.

### `updateCells` `note` field → `fmt_note()` — cell notes

Anchor an assumption/source note on a cell (the small black corner
triangle):

```r
fmt_note(sid, row = 5L, col = 2L, text = "Source: FY26 budget v3, row 41")   # B5
fmt_note(sid, 5L, 2L, "")                                                    # clears it
```

It builds one `updateCells` request with `fields = "note"`, so the cell's
value and format stay as they are (checked live in `scripts/selftest.R`). `row`
and `col` are 1-based, as in `fmt_cells()`; `text` must be one non-`NA` string,
and `""` clears the note. The raw request it sends:

```r
list(updateCells = list(
  range  = grid_range(sid, 5L, 5L, 2L, 2L),   # B5
  rows   = list(list(values = list(list(note = "Source: FY26 budget v3, row 41")))),
  fields = "note"
))
```

⚠ Sheets' PDF export prints every note as a `[n]` marker plus an extra page, so
keep notes off a tab you export for `visual_qa()` or `export_sheet_as_pdf()`.

## `batch_format()` — sending it all at once

Always use `batch_format()` from `gs_helpers.R` rather than rolling
`request_generate` + `request_make` directly. It checks HTTP status —
without that check, an HTTP 400 returns silently and your formatting
never applies.

```r
batch_format(ss, list(
  fmt_gridlines(sid, show = FALSE),
  fmt_freeze(sid, rows = 1L),
  fmt_cells(sid, 1, 1, 1, 6,
            font_family = "Arial", bold = TRUE, font_size = 12,
            font_color = COL_WHITE, bg_color = COL_BRAND, halign = "CENTER"),
  fmt_merge(sid, 1, 1, 1, 6),
  fmt_col_width(sid, 1, 1, 280),
  fmt_borders(sid, 1, 1, 1, 6,
              bottom = list(style = "SOLID_MEDIUM", color = COL_BRAND))
))
```

`batchUpdate` is **atomic** — one bad request fails ALL requests in the
batch. Track this when adding new request types: validate one at a time
before bundling everything together.

### Verifying success & per-tab isolation

Two failure modes that cost real debugging time:

1. **A 400 doesn't throw.** `batch_format()` only `message()`s the HTTP
   error (and that line can scroll off or hide behind `grep | tail`), so a
   `tryCatch` will NOT catch it and a logged "N/N applied" can be false.
   Either pass **`strict = TRUE`** (stops on HTTP ≥ 400) or **re-read the
   live state** afterwards to confirm — don't trust the self-report.

2. **One bad request nukes the whole batch.** When applying *independent*
   cosmetic ops across many tabs (merges, banners, freezes), send **one
   `batch_format()` per tab** so a single failure (e.g. a freeze↔merge
   conflict on one tab — see [pitfalls.md](pitfalls.md)) can't take down
   the rest, and the per-tab "applied" counts pinpoint the culprit.

```r
for (sid in tab_sids) {
  reqs <- build_requests_for(sid)
  batch_format(ss, reqs)            # isolated; strict=TRUE to fail loudly
}
```

⚠ **Freeze ↔ merge:** a full-width `A:*` merge and a frozen column A are
mutually exclusive in BOTH directions (merge-across-freeze and
freeze-splits-merge both 400). Banner tabs that merge column A must use
`frozenColumnCount = 0`. Full treatment in [pitfalls.md](pitfalls.md).

## The composable-formatting pattern

For multi-section tabs, build pure sub-functions that return `list(...)`
of requests (no API calls inside). The caller assembles everything and
sends one big `batch_format()`.

```r
fmt_global <- function(sid, last_row) {
  c(
    list(
      fmt_gridlines(sid, show = FALSE),
      fmt_freeze(sid, rows = 4L),
      fmt_col_width(sid, 1, 1, 20),
      fmt_col_width(sid, 3, 3, 310),
      apply_style(sid, 1, last_row, 1, 8, STYLE_BODY)   # global default FIRST
    ),
    fmt_group_cols(sid, 21, 26)   # c() flattens the 2 requests
  )
}

fmt_pnl_section <- function(sid) {
  list(
    fmt_borders(sid, 10, 35, 3, 8,
                top    = list(style = "DOUBLE", color = COL_BRAND),
                bottom = list(style = "DOUBLE", color = COL_BRAND)),
    fmt_cells(sid, 11, 35, 4, 6,
              numfmt_type = "NUMBER", numfmt_pattern = '$#,##0;($#,##0);"-"')
  )
}

# Assemble + send in ONE call
all_fmt <- c(
  fmt_global(sid, last_row),
  fmt_pnl_section(sid)
)
batch_format(ss, all_fmt)
```

Three principles:
1. Apply `STYLE_BODY` (or your global default) to the full sheet range
   FIRST, then override with section-specific styles.
2. Pure functions — never call `batch_format()` inside a sub-function.
3. Use `c()` to flatten, especially around `fmt_group_*()`.
