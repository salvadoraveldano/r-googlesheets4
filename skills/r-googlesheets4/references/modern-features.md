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
                      showTotals = TRUE)),
  values = list(list(sourceColumnOffset = 4L,         # sum col 5
                     summarizeFunction = "SUM",
                     name = "Total $"))
)
```

`summarizeFunction` ∈ `SUM` / `AVERAGE` / `COUNTA` / `COUNT` /
`COUNT_UNIQUE` / `MAX` / `MIN` / `MEDIAN` / `PRODUCT` / `STDEV` /
`STDEVP` / `VAR` / `VARP` / `CUSTOM`.

⚠️ **Source data must be committed first.** If the pivot's
`source_range` doesn't have data yet, the pivot renders empty. Order:
flush data → wait briefly → batchUpdate the pivot.

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

## Protected ranges (`addProtectedRange`)

Lock a range from edits. With `warning_only = TRUE`, edits show a
warning but are not blocked. With `warning_only = FALSE` plus
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

The owner of the spreadsheet always retains edit access regardless of
the protected-range editor list.

## Slicers (`addSlicer`)

Filter chips anchored at a cell, filtering charts and pivot tables that
share the source data.

```r
fmt_slicer(
  sheet_id = sid,
  source_sheet_id = data_sid,
  source_range = c(1L, 1000L, 1L, 12L),
  column_index = 2L,           # 0-based col within source the slicer filters
  anchor_row = 1L, anchor_col = 12L,
  title = "Filter by Department",
  size = c(220L, 35L)
)
```

Slicers stay in sync with charts as you change filters in the UI — no
formula plumbing required on your side.

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
