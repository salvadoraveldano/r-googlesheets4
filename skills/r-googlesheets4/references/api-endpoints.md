# API Endpoints Reference

All endpoints reachable via `googlesheets4::request_generate(endpoint = "...")`.

| Endpoint                                                  | Use                                                              |
|-----------------------------------------------------------|------------------------------------------------------------------|
| `sheets.spreadsheets.create`                              | Create a new spreadsheet                                         |
| `sheets.spreadsheets.get`                                 | Get metadata (and read formats — see `dump_reference_tab()`)     |
| `sheets.spreadsheets.batchUpdate`                         | **Formatting, merges, borders, validation, conditional formatting, charts, banding, pivots, filter views, slicers, protected ranges** |
| `sheets.spreadsheets.values.get`                          | Read cell values from one range                                  |
| `sheets.spreadsheets.values.update`                       | Write cell values to one range                                   |
| `sheets.spreadsheets.values.append`                       | Append rows below the last data row                              |
| `sheets.spreadsheets.values.clear`                        | Clear cell values from one range (keeps formats: `gs_clear_values()`) |
| `sheets.spreadsheets.values.batchGet`                     | Read multiple ranges in one call. ⚠ A vector `ranges` fails in `request_generate()` (`values must be length 1`): use `read_values()`, one `values.get` per range |
| `sheets.spreadsheets.values.batchUpdate`                  | Write multiple ranges in one call (used by `flush_writes()`)     |
| `sheets.spreadsheets.values.batchClear`                   | Clear multiple ranges in one call                                |
| `sheets.spreadsheets.values.batchGetByDataFilter`         | Read by filter (e.g., named range)                               |
| `sheets.spreadsheets.values.batchUpdateByDataFilter`      | Write by filter                                                  |
| `sheets.spreadsheets.values.batchClearByDataFilter`       | Clear by filter                                                  |
| `sheets.spreadsheets.sheets.copyTo`                       | Copy sheet to another spreadsheet                                |
| `sheets.spreadsheets.getByDataFilter`                     | Get metadata by filter                                           |
| `sheets.spreadsheets.developerMetadata.get`               | Get developer metadata                                           |
| `sheets.spreadsheets.developerMetadata.search`            | Search developer metadata                                        |

## Most-used `batchUpdate` request keys

Each entry in the `requests` list is a one-key dict. The key names below
all live under `sheets.spreadsheets.batchUpdate`.

| Request key                 | Helper                          | What it does                                       |
|-----------------------------|---------------------------------|----------------------------------------------------|
| `repeatCell`                | `fmt_cells()`                   | Font, fill, numfmt, alignment                      |
| `mergeCells`                | `fmt_merge()`                   | Merge a rectangle                                  |
| `unmergeCells`              | `fmt_unmerge()`                 | Unmerge                                            |
| `updateBorders`             | `fmt_borders()`                 | Borders on all sides                               |
| `updateSheetProperties`     | `fmt_gridlines()`, `fmt_freeze()`, `fmt_tab_color()`, `fmt_tab_order()` | Sheet-level config, tab order |
| `updateDimensionProperties` | `fmt_col_width()`, `fmt_row_height()` | Width / height in pixels                     |
| `addDimensionGroup`         | `fmt_group_cols()`, `fmt_group_rows()` (returns 2 requests) | Group + collapse |
| `setDataValidation`         | `fmt_dropdown()`, `fmt_dropdown_range()`, `fmt_validation()` | Dropdowns, number, date and custom rules |
| `addNamedRange`             | `fmt_named_range()`             | Named ranges                                       |
| `updateSpreadsheetProperties` | `fmt_theme_colors()`          | Theme colors (pie slice colors follow the accents) |
| `addConditionalFormatRule`  | `fmt_cond_negative()`, `fmt_cond_color_scale()`, `fmt_cond_formula()`, `fmt_cond_text_equals()`, `fmt_cond_text()`, `fmt_cond_number()` | Conditional formatting |
| `deleteConditionalFormatRule` | `fmt_delete_cond_rules()`     | Delete (use descending indices)                    |
| `addBanding`                | `fmt_banding()`                 | Alternating row colors                             |
| `updateCells` (with `pivotTable`) | `fmt_pivot_table()`        | Pivot tables                                       |
| `addFilterView`             | `fmt_filter_view()`             | Saved per-user filter view                         |
| `setBasicFilter` / `clearBasicFilter` | `fmt_basic_filter()` (clear: inline) | The tab's one filter (set replaces it; idempotent) |
| `addProtectedRange`         | `fmt_protected_range()`         | Lock a range                                       |
| `addSlicer`                 | `fmt_slicer()`                  | Filter chip for charts/pivots                      |
| `addChart`                  | `fmt_chart_basic()`, `fmt_chart_bar()`, `fmt_chart_waterfall()`, `fmt_chart_pie()` | Charts (pie and doughnut) |
| `deleteEmbeddedObject`      | `gs_reset_tabs()` (inline)      | Delete a chart (`chartId`) or slicer (`slicerId`) by `objectId` |
| `deleteBanding` / `deleteProtectedRange` / `deleteFilterView` | `gs_reset_tabs()` (inline) | Delete by `bandedRangeId` / `protectedRangeId` / `filterId` |
| `deleteDimensionGroup` / `deleteNamedRange` | `gs_reset_tabs()` (inline) | Delete one group level, or a name. ⚠ Deleting a named range turns every formula that uses it into `#REF!` for good |
| `findReplace`               | `fmt_find_replace()`            | Bulk find/replace                                  |
| `autoResizeDimensions`      | `fmt_auto_resize_cols()`        | Auto-fit column widths                             |
| `insertDimension`           | —                               | Insert blank rows / columns                        |
| `deleteDimension`           | —                               | Delete rows / columns                              |
| `moveDimension`             | —                               | Move rows / columns                                |
| `cutPaste` / `copyPaste`    | —                               | Move/copy a sub-block, auto-rewrite formulas       |
| `addSheet` / `deleteSheet`  | (use `sheet_add` / `sheet_delete`) | Tab management                                  |
| `addTable` / `updateTable` / `deleteTable` | (inline — no helper yet; `gs_reset_tabs()` runs `deleteTable`) | Sheets Tables. **The only API path to chip-style dropdowns** (set `columnType: "DROPDOWN"` on a table column). See [modern-features.md](modern-features.md) § "Sheets Tables & chip-style dropdowns". |

## Reference URL

[Google Sheets API v4 reference](https://developers.google.com/sheets/api/reference/rest)

For request shapes not covered by helpers, look up the request key in
the API docs and build the list manually:

```r
my_request <- list(insertDimension = list(
  range = list(sheetId = sid, dimension = "ROWS",
               startIndex = 0L, endIndex = 5L),
  inheritFromBefore = FALSE
))
batch_format(ss, list(my_request))
```

## URL-encoding ranges: path vs query

A1 ranges appear in two different places in REST calls, with **opposite** encoding rules:

```r
# 1. Range in the URL PATH (values.get: "v4/spreadsheets/{spreadsheetId}/values/{range}")
#    → MUST be encoded yourself, or quotes/! in "'My Tab'!A1:C5" break the URL:
params = list(spreadsheetId = id,
              range = utils::URLencode("'My Tab'!A1:C5", reserved = TRUE), ...)

# 2. Range in a QUERY param (spreadsheets.get: "...?ranges='My Tab'!A1:C5&fields=...")
#    → pass RAW; gargle/httr encodes query params for you.
#    Pre-encoding here DOUBLE-encodes (%2527...) and the API returns
#    "Unable to parse range" or silently matches nothing:
params = list(spreadsheetId = id,
              ranges = "'My Tab'!A1:C5", fields = fld, ...)
```

Rule of thumb: encode only what you interpolate into the **path** segment; leave `params` list values raw.

Exception: `values.update` goes through `request_generate()` with the range also
copied into the request body, so an encoded range fails HTTP 400 (`does not
match value's range`) and a raw one with a space, quote or `&` never leaves R.
Write through `values.batchUpdate` (`flush_writes()`; the range sits in the JSON
body) or `range_write()` instead. For reads use `read_values()`.
