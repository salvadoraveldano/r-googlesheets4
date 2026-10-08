# Modern API Features

API surface that the original skill didn't cover. Helpers in
`scripts/gs_modern.R`.

**Contents:**
[Banded ranges](#banded-ranges-addbanding) ·
[Pivot tables](#pivot-tables-updatecellspivottable) ·
[Filter views](#filter-views-addfilterview) ·
[Protected ranges](#protected-ranges-addprotectedrange) ·
[Slicers](#slicers-addslicer) ·
[Image embedding](#image-embedding-image) ·
[Bulk find/replace](#bulk-findreplace-findreplace) ·
[Auto-resize](#auto-resize-autoresizedimensions) ·
[Sheets Tables & chip dropdowns](#sheets-tables--chip-style-dropdowns-addtable--updatetable--deletetable) ·
[Combining new features](#combining-new-features)

## Banded ranges (`addBanding`)

Native alternating-row banding. Cleaner and faster than per-row
`repeatCell` for table styling.

```r
fmt_banding(sheet_id   = sid,
            start_row  = 2L, end_row = 100L,
            start_col  = 1L, end_col = 10L,
            header_color = COL_BRAND,
            first_band   = COL_WHITE,
            second_band  = hex_to_color("F3F3F3"),
            footer_color = COL_LIGHT_GRAY)
```

⚠️ **Conflict with repeatCell.** Banded background colors get
overridden by any later `repeatCell` that sets `backgroundColor` on the
same cells. Apply banding LAST in your batch, or skip per-row bg colors
elsewhere.

## Pivot tables (`updateCells.pivotTable`)

Pivots in the API are an `updateCells` request whose value is a
`pivotTable` object. The pivot lives at the anchor cell and expands
right/down based on rows/columns/values.

```r
fmt_pivot_table(
  sheet_id = pivot_tab_sid,
  anchor_row = 1L, anchor_col = 1L,
  source_sheet_id = data_sid,
  source_range = c(1L, 1000L, 1L, 12L),
  rows = list(list(sourceColumnOffset = 0L,           # group by col 1
                   showTotals = TRUE,
                   sortOrder = "ASCENDING")),
  columns = list(list(sourceColumnOffset = 2L,        # group by col 3
                      showTotals = TRUE,
                      sortOrder = "ASCENDING")),
  values = list(list(sourceColumnOffset = 4L,         # sum col 5
                     summarizeFunction = "SUM",
                     name = "Total $"))
)
```

Every `rows` / `columns` group needs a `sortOrder`: the API answers HTTP 400
"No sort order specified" without one (the helper fills in `"ASCENDING"` when
you leave it out).

`summarizeFunction` ∈ `SUM` / `AVERAGE` / `COUNTA` / `COUNT` /
`COUNT_UNIQUE` / `MAX` / `MIN` / `MEDIAN` / `PRODUCT` / `STDEV` /
`STDEVP` / `VAR` / `VARP` / `CUSTOM`.

⚠️ **Source data must be committed first.** If the pivot's
`source_range` doesn't have data yet, the pivot renders empty. Order:
flush data → wait briefly → batchUpdate the pivot.

### Pivot filters

`filters` is a **named list keyed by the 0-based column offset within
`source_range`** (the key is a string: `"5"`, not `5`). Each value is a
`PivotFilterCriteria`; `visibleValues` keeps only the listed values (live-checked
below). The offset counts from the first column of `source_range`, so it moves
if you change where `source_range` starts. (Checked live with a source range
starting at column B: key `"0"` filtered that range's first column, and the
sheet-column reading `"1"` gave an empty pivot. A slicer's `column_index` is the
opposite, an absolute sheet column.)

```r
# Source Data!A1:D21 = Category, Type, Month, Amount (header on row 1).
# Offset 1 is "Type": keep only the Expense rows.
fmt_pivot_table(
  sheet_id = pivot_tab_sid, anchor_row = 4L, anchor_col = 2L,
  source_sheet_id = data_sid, source_range = c(1L, 21L, 1L, 4L),
  rows    = list(list(sourceColumnOffset = 0L, showTotals = TRUE, sortOrder = "ASCENDING")),
  columns = list(list(sourceColumnOffset = 2L, showTotals = TRUE, sortOrder = "ASCENDING")),
  values  = list(list(sourceColumnOffset = 3L, summarizeFunction = "SUM", name = "Spent")),
  filters = list("1" = list(visibleValues = list("Expense")))
)
```

Checked live: with that filter the Income rows dropped out and the Grand Total
equalled the sum of the Expense amounts.

### Finding the rendered pivot extent

The API returns the pivot's *definition* at the anchor cell, not its size, and
the size changes with the data (a new month adds a column and pushes Grand
Total right). To format the body, shade it or place something beside it, read
the rendered values and measure them. `values.get` drops trailing blank rows
and columns, so a block read from the anchor to the right edge of the sheet
starts with the pivot; cut it at the first blank row:

```r
# Pivot anchored at B4 on a tab named "Trends"
rng  <- utils::URLencode("'Trends'!B4:Z", reserved = TRUE)    # open-ended: down to the last row
resp <- googlesheets4::request_make(googlesheets4::request_generate(
  "sheets.spreadsheets.values.get",
  params = list(spreadsheetId = as.character(ss), range = rng,
                valueRenderOption = "UNFORMATTED_VALUE")))
pv     <- gargle::response_process(resp)$values   # list of rows, each starting at column B
n_rows <- match(0L, lengths(pv), nomatch = length(pv) + 1L) - 1L   # stop at the first blank row
n_cols <- max(lengths(pv[seq_len(n_rows)]))       # pivot = B4 .. column B + n_cols - 1, row 4 + n_rows - 1
total_row <- 4L - 1L + which(vapply(pv[seq_len(n_rows)], function(r)
  length(r) > 0L && identical(as.character(r[[1L]]), "Grand Total"), NA))
```

Checked live on a 6-row by 7-column pivot (Category x Month with totals) with a
caption written two rows under it: the snippet returned 6 and 7. Things that
break the measurement: a note in a cell to the right of the pivot on one of its
rows adds a column, and a pivot with data in its way does not render at all.
The `batchUpdate` still returns HTTP 200 in that case, but the anchor cell shows
an error ("Array result was not expanded because it would overwrite data in
D6"), so a block of one row means something is in the way. Keep the area right
of and below the pivot empty, and leave a blank row before anything under it.

The range goes in the URL path, so it must be `URLencode(reserved = TRUE)`
(the `'`, `!` and `:` otherwise break the request). Wait a few seconds after the
pivot's `batchUpdate` before reading, and use the measured rows and columns in
the same script for the heatmap, number format and column widths. A pivot that
the data can widen (a new month, a new category) needs the formatting range
a column or two wider than today's extent.

## Filter views (`addFilterView`)

Saved per-user filter/sort views without changing the underlying data.
Each user sees their own view.

```r
fmt_filter_view(
  sheet_id  = sid,
  start_row = 1L, end_row = 1000L,
  start_col = 1L, end_col = 10L,
  title = "Active accounts only",
  sort_specs = list(list(dimensionIndex = 4L, sortOrder = "DESCENDING")),
  criteria = list(`0` = list(condition = list(
    type = "TEXT_EQ",
    values = list(list(userEnteredValue = "Active"))
  )))
)
```

`criteria` keys are 0-based column indices within the range.

### Basic filter (`setBasicFilter`)

`fmt_basic_filter(sid, start_row, end_row, start_col, end_col)` sets the tab's
one filter (the header-row funnel). A second call replaces it, so it is safe to
rerun; a slicer on the same range coexists with it. `gs_reset_tabs()` clears it
(`clearBasicFilter`).

## Protected ranges (`addProtectedRange`)

Lock a range, or a whole tab, from edits. With `warning_only = TRUE`, edits
show a warning but are not blocked. With `warning_only = FALSE` plus
`editor_emails`, edits are enforced.

```r
# Advisory only
fmt_protected_range(sid, 1L, 100L, 1L, 5L,
                    description = "Don't edit — formulas",
                    warning_only = TRUE)

# Enforced — only listed editors can change
fmt_protected_range(sid, 1L, 100L, 1L, 5L,
                    description = "Locked: finance team only",
                    warning_only = FALSE,
                    editor_emails = c("admin@example.com", "lead@example.com"))
```

### Whole tab, with the input cells left open

Leave the four bounds out to protect the **whole sheet**, and pass the cells
people may still edit as `unprotected_ranges` (a list of `grid_range()`; a
single `grid_range()` also works). This is the "formulas are protected, inputs
stay open" pattern:

```r
fmt_protected_range(sid,
                    description = "Formulas. Edit only the yellow input cells",
                    unprotected_ranges = list(grid_range(sid, 5L, 9L, 3L, 3L),    # C5:C9
                                              grid_range(sid, 2L, 2L, 6L, 6L)))   # F2
```

The API only accepts `unprotectedRanges` on a protection that covers the whole
sheet (a bounded range answers HTTP 400 "unprotectedRanges are only allowed on
ProtectedRanges covering a whole sheet"), so `fmt_protected_range()` stops with
that explanation before sending the request. A whole-sheet protection can sit
next to bounded ones on the same tab. All of this was run live with
`warning_only = TRUE`.

Read the protections back, and remove one, by id:

```r
meta <- gargle::response_process(googlesheets4::request_make(googlesheets4::request_generate(
  "sheets.spreadsheets.get",
  params = list(spreadsheetId = as.character(ss), fields = "sheets(properties(title),protectedRanges)"))))
# meta$sheets[[i]]$protectedRanges[[j]]: protectedRangeId, description, warningOnly, range, unprotectedRanges
batch_format(ss, list(list(deleteProtectedRange = list(protectedRangeId = id))), strict = TRUE)
```

`addProtectedRange` never replaces: adding the same bounded protection twice
leaves two, and a tab can hold only ONE whole-sheet protection (the second is
rejected with HTTP 400 `Sheet "<tab>" already has sheet protection`). So when a
build script is re-run in place, delete the old protections by id first.

The owner of the spreadsheet always retains edit access regardless of
the protected-range editor list.

## Slicers (`addSlicer`)

A filter chip anchored at a cell. It filters the **rows of its own data
range**, and charts and pivot tables built on that range. It does **not** move
cells that are formulas over the data (KPI cards, `SUMIFS`, a `QUERY`): drive
those from a dropdown cell instead. (Checked live with a slicer hiding rows:
`SUM`, `SUMIFS` and even `SUBTOTAL(109, ...)` over the range still returned the
full-range values.)

```r
fmt_slicer(
  sheet_id = sid,
  source_sheet_id = data_sid,
  source_range = c(1L, 1000L, 1L, 12L),   # header row first
  column_index = 2L,           # 0-based SHEET column (A = 0) the slicer filters
  anchor_row = 1L, anchor_col = 14L,
  title = "Filter by Department",
  size = c(220L, 35L)
)
```

The request shape is `addSlicer.slicer.spec = list(dataRange, columnIndex, title,
applyToPivotTables)`: `columnIndex` (and an optional `filterCriteria`) sit
**directly on the spec**. There is no `filterSpec` wrapper; sending one is
rejected with HTTP 400 `Unknown name "filterSpec"` (the helper used to build it).

- `column_index` is the 0-based column of the **sheet**, not an offset inside
  `source_range`: with a source range starting at column B, `column_index = 2`
  filters column C. (Checked live by hiding one value and reading which rows
  went `hiddenByFilter`.) Pick a column inside the source range.
- `filter_criteria = list(hiddenValues = list("Income"))` starts the slicer with
  those values hidden. `FilterCriteria` has `hiddenValues` and `condition`, not
  `visibleValues`. Omit it (the default) to start with everything shown.
- `apply_to_pivot_tables = FALSE` keeps pivot tables on the same data out of it
  (default `TRUE`). It is not a per-slicer setting: it applies to ALL slicers on
  that data range, and the last slicer created sets it (checked live on one range
  and tab: adding a `FALSE` slicer flipped an existing `TRUE` one, and deleting it
  did not flip it back).
- A slicer coexists with a `setBasicFilter` on the same range.

Read slicers back with `fields = "sheets(slicers)"`, and delete one by id (a
slicer is an embedded object):

```r
meta <- gargle::response_process(googlesheets4::request_make(googlesheets4::request_generate(
  "sheets.spreadsheets.get",
  params = list(spreadsheetId = as.character(ss), fields = "sheets(properties(title),slicers)"))))
# meta$sheets[[i]]$slicers[[j]]: slicerId, spec (columnIndex, title, ...), position
batch_format(ss, list(list(deleteEmbeddedObject = list(objectId = slicer_id))), strict = TRUE)
```

Slicers stack: adding the same one twice leaves two (checked live), so when a
build script is re-run in place, delete the old ones by id first.

## Image embedding (`=IMAGE()`)

Two modes:

```r
# IN_CELL — uses =IMAGE() formula. Image scales inside the cell.
fmt_image_cell(sid, row = 5L, col = 3L,
               image_url = "https://example.com/logo.png",
               mode = "IN_CELL")

# OVER_CELL — embedded object positioned over the anchor cell.
fmt_image_cell(sid, row = 5L, col = 3L,
               image_url = "https://example.com/logo.png",
               mode = "OVER_CELL", size = c(200L, 200L))
```

Caveats:
- IN_CELL is the simpler path — works in regular reads / exports.
- OVER_CELL needs an actual image upload via the Drive API to be useful;
  the helper exposes the position request but for production overlay
  images, prefer `drive_upload()` + a chart workaround.

## Bulk find/replace (`findReplace`)

Replace text across a sheet, the whole spreadsheet, or a range. Supports
case-sensitive, whole-cell, regex modes.

```r
fmt_find_replace(find_text = "FY2025", replacement = "FY2026",
                 all_sheets = TRUE,
                 match_case = TRUE)

fmt_find_replace(find_text = "^DEPT_(\\w+)",
                 replacement = "Dept: $1",
                 sheet_id = sid,
                 search_by_regex = TRUE)
```

Common use: bulk year rollover when copying last year's workbook.

## Auto-resize (`autoResizeDimensions`)

Programmatic equivalent of double-clicking the column-width handle.

```r
fmt_auto_resize_cols(sid, start_col = 1L, end_col = 10L)
```

Use it batched alongside other formatting requests rather than calling
`range_autofit()` separately (one less API call).

## Sheets Tables & chip-style dropdowns (`addTable` / `updateTable` / `deleteTable`)

Sheets Tables (announced 2024) wrap a range with column-typed semantics:
TEXT, NUMERIC, DATE, CHECKBOX, DROPDOWN, etc. The **only** purpose this
skill cares about: when a column is `columnType: "DROPDOWN"`, its cells
render as **chip-style** dropdowns — the display style is otherwise not
reachable via the Sheets API. See [data-validation.md](data-validation.md)
§ "Chip vs Arrow vs Plain Text".

**Two-step pattern (mandatory).** A single-step `addTable` carrying
`columnProperties` with `columnType: "DROPDOWN"` returns
**`500 INTERNAL`** from the API. Confirmed reproducible. Split into:

```r
# Step 1: addTable plain (no columnProperties)
add_req <- list(addTable = list(table = list(
  name = "Assignments",
  range = list(sheetId = sid,
               startRowIndex = 2L, endRowIndex = 20L,    # rows 3-20 (header + 17 data rows)
               startColumnIndex = 3L, endColumnIndex = 7L)  # cols D-G
)))
add_resp <- batch_format(ss, list(add_req))
new_tid <- add_resp$replies[[1]]$addTable$table$tableId

# Step 2: updateTable to set DROPDOWN column types
mk_dropdown_col <- function(idx, name, values) list(
  columnIndex = idx,
  columnName  = name,
  columnType  = "DROPDOWN",
  dataValidationRule = list(condition = list(
    type = "ONE_OF_LIST",
    values = lapply(values, function(v) list(userEnteredValue = as.character(v)))
  ))
)
update_req <- list(updateTable = list(
  table = list(
    tableId = new_tid,
    columnProperties = list(
      mk_dropdown_col(0L, "Region",   regions),  # indices RELATIVE to table range
      mk_dropdown_col(1L, "Team",     teams),
      mk_dropdown_col(2L, "Product",  products),
      mk_dropdown_col(3L, "Status",   statuses)
    ),
    rowsProperties = list(
      headerColorStyle     = list(rgbColor = list(red = 0.14, green = 0.34, blue = 0.77)),
      firstBandColorStyle  = list(rgbColor = list(red = 1, green = 1, blue = 1)),  # neutralize
      secondBandColorStyle = list(rgbColor = list(red = 1, green = 1, blue = 1))
    )
  ),
  fields = "columnProperties,rowsProperties"
))
batch_format(ss, list(update_req))
```

### Critical caveats

1. **Banding is auto-applied** — addTable imposes alternating row colors
   plus a dark-green header by default. To make the table visually
   invisible (preserve your existing palette), set both `firstBandColorStyle`
   and `secondBandColorStyle` to white (or your data-row bg color) and
   override `headerColorStyle` to match your existing header.
2. **Grid bounds are enforced** — the table range cannot exceed the
   sheet's `gridProperties.columnCount` / `rowCount`. Error:
   `Range exceeds grid limits. Max rows: N, max columns: N`. Default
   new-sheet col count is 26 (A–Z) — extend via
   `updateSheetProperties.gridProperties` first if you need cols past Z.
3. **`columnIndex` in `columnProperties` is RELATIVE to the table range**,
   not the sheet. A table starting at col D with two columns has
   `columnIndex: 0` for D and `1` for E. Error otherwise:
   `Column index must be between 0 (inclusive) and the number of columns
   (exclusive) in the table.`
4. **Pre-existing per-cell `dataValidation` conflicts** — clear it before
   addTable via `updateCells` with `fields = "dataValidation"`. The
   table's `columnProperties.dataValidationRule` is what governs once
   the table exists.
5. **Pre-existing `userEnteredFormat` is preserved** by addTable, but
   the effective format includes the table's banding layer underneath.
   If you want explicit per-row bg colors to win, re-apply them after
   the table is created (`updateCells` with `fields = "userEnteredFormat"`).
6. **Cell values survive** — addTable doesn't touch `userEnteredValue`.
   Comma-list strings like `"north, south"` remain, and Sheets renders
   them as multi-chip in the chip UI automatically.
7. **Banding-conflict on re-run** — addTable on a range that already
   has banding returns
   `You cannot add alternating background colors to a range that already
   has alternating background colors.` Either deleteTable first
   (idempotent re-run pattern) or `deleteBanding` if the banding is
   freestanding.
8. **Idempotency** — before re-running an addTable script, look up the
   existing table by name and `deleteTable` it. Tables are addressed by
   `tableId` (server-assigned), not by name; the name is just a label.

### Looking up / inspecting tables

```r
resp <- googlesheets4::request_make(googlesheets4::request_generate(
  "sheets.spreadsheets.get",
  params = list(spreadsheetId = ss_id,
                fields = "sheets(properties(sheetId,title),tables(tableId,name,range,columnProperties))")
))
body <- gargle::response_process(resp)
for (s in body$sheets) for (t in s$tables) cat(t$name, "→", t$tableId, "\n")
```

### Other DROPDOWN gotchas

- `strict` field on `columnProperties.dataValidationRule` is honored —
  set `strict = FALSE` to suppress validation warnings on pre-filled
  comma-list values (otherwise Sheets flags them red).
- Chip-style dropdowns make the "Multiple values" toggle **available in the
  UI** — but the toggle itself is NOT API-controllable; a user must flip it
  once per copy, so ship the instruction banner. Canonical treatment:
  [data-validation.md](data-validation.md) § "Allow multiple values toggle".
- For non-chip needs, there is no reason to wrap a range in a Table —
  use the plain `setDataValidation` request (the `fmt_dropdown()` helper).

## Combining new features

Banded ranges + filter views + protected ranges work well together for
"editable analyst tab" pattern:

```r
batch_format(ss, list(
  fmt_banding(sid, 1, 1000, 1, 10, header_color = COL_BRAND,
              first_band = COL_WHITE, second_band = hex_to_color("F3F3F3")),
  fmt_freeze(sid, rows = 1L),
  fmt_filter_view(sid, 1, 1000, 1, 10, title = "Default sort"),
  fmt_protected_range(sid, 1, 1, 1, 10,                  # protect header
                      description = "Header — do not edit",
                      warning_only = FALSE,
                      editor_emails = c("admin@example.com")),
  fmt_auto_resize_cols(sid, 1, 10)
))
```
