# Data Validation (Dropdowns)

## Dropdown from a list

```r
fmt_dropdown(sheet_id = sid,
             start_row = 2L, end_row = 100L,
             start_col = 3L, end_col = 3L,
             values = c("Fixed", "Variable", "SaaS"))
```

`strict = TRUE` (default in the helper) rejects values not in the list.
`showCustomUi = TRUE` shows the dropdown chevron.

## Dropdown referencing a range

```r
fmt_dropdown_range(sid,
                   start_row = 2L, end_row = 100L,
                   start_col = 3L, end_col = 3L,
                   source_range = "=Lists!B2:B13")
```

The source_range string is what gets typed into the validation rule's
"From a range" field — must start with `=` and use `'Sheet Name'!A1:B10`
notation for tabs with spaces.

## Multiple types — checkbox, date

The Sheets API supports more validation types via `setDataValidation`:

| Condition type      | Use                                                   |
|---------------------|-------------------------------------------------------|
| `ONE_OF_LIST`       | Picklist from values (above)                          |
| `ONE_OF_RANGE`      | Picklist from a range (above)                         |
| `BOOLEAN`           | Checkbox                                              |
| `DATE_BETWEEN`      | Date in a range                                       |
| `NUMBER_BETWEEN`    | Number in a range                                     |
| `TEXT_CONTAINS`     | Text contains substring                               |
| `CUSTOM_FORMULA`    | Arbitrary formula returning TRUE/FALSE                |

`BOOLEAN` renders an **interactive checkbox** in the cell (the TRUE/FALSE
cell value drives its state — write `TRUE`/`FALSE` to pre-set it):

```r
list(setDataValidation = list(
  range = grid_range(sid, 2L, 100L, 5L, 5L),   # E2:E100
  rule  = list(condition = list(type = "BOOLEAN"))
))
```

Example custom — only allow positive numbers in B2:B100:

```r
list(setDataValidation = list(
  range = grid_range(sid, 2L, 100L, 2L, 2L),
  rule = list(
    condition = list(
      type = "CUSTOM_FORMULA",
      values = list(list(userEnteredValue = "=B2>0"))
    ),
    inputMessage = "Enter a positive number",
    strict = TRUE
  )
))
```

## Clearing validation

To remove validation, send the same range with `rule = NULL`:

```r
list(setDataValidation = list(
  range = grid_range(sid, 2L, 100L, 3L, 3L),
  rule = NULL
))
```

(Or just set the validation again on the empty range — it overwrites.)

Alternative — clear via `updateCells` fields mask (works the same way `userEnteredValue` clears do, per [pitfalls.md](pitfalls.md)):

```r
list(updateCells = list(
  range = grid_range(sid, 2L, 100L, 3L, 3L),
  fields = "dataValidation"
))
```

## Chip vs Arrow vs Plain Text — display style is NOT in DataValidationRule

The Google Sheets UI lets users pick a display style for a dropdown:
**Chip** (colored chips, multi-select capable), **Arrow** (legacy caret),
or **Plain text** (no UI). `fmt_dropdown()` / `fmt_dropdown_range()` /
any `setDataValidation` request **always render as Arrow** because the
Sheets API v4 `DataValidationRule` schema does not expose this field —
it has only `condition`, `inputMessage`, `strict`, `showCustomUi`.
`showCustomUi` is **not** the chip switch; it only toggles whether the
caret-dropdown UI appears at all.

Known limitation, open feature request:
[googleapis/google-api-python-client#2676](https://github.com/googleapis/google-api-python-client/issues/2676)
(Oct 2025, no resolution as of this writing). Also see issue tracker
[#296461001](https://issuetracker.google.com/issues/296461001).

**Workaround for chip rendering:** wrap the range in a Sheets Table and
set the column's `columnType: "DROPDOWN"`. See [modern-features.md](modern-features.md)
§ "Sheets Tables & chip-style dropdowns" for the pattern.

**When to use which:**

| Need | Use |
|---|---|
| Single-select dropdown, Arrow style is fine | `fmt_dropdown()` (this file, top) |
| Multi-select chips, values render as chips | Tables API — see `modern-features.md` |
| Need `strict=FALSE` on pre-filled cells | Build inline; `fmt_dropdown()` defaults `strict=TRUE` |

The multi-select chip UI (multiple chips per cell) is only available on
chip-style dropdowns. After applying chip rendering via the Tables API,
users can also right-click → Data validation → toggle "Multiple values"
to enable explicit multi-chip mode.

### "Allow multiple values" toggle — UI only, NOT API-controllable

The chip rendering and the "Allow multiple values" toggle are **two
different settings**, both required for true multi-chip editing. Chip
display is reachable via the Tables API; "Allow multiple values" is
**not** exposed by any of:

- REST `DataValidationRule`: no `allowMultiple` / `multipleValues` / similar field
- Tables API `columnProperties.dataValidationRule`: same DataValidationRule schema, same gap
- Apps Script `DataValidationBuilder`: no `setMultipleValuesEnabled()` or equivalent

Open feature request:
[googleapis/google-api-python-client#2676](https://github.com/googleapis/google-api-python-client/issues/2676)
(filed Oct 2025, no resolution as of writing). Without the toggle ON,
chip dropdowns still behave as **single-select per click** — picking a
new chip replaces the cell value rather than appending.

**Mitigation (mandatory pattern for chip-dropdown builds):** ship the
workbook with a prominent in-sheet **instruction banner** that tells the
opener to right-click any cell in each dropdown column → Data validation
→ toggle "Allow multiple values" ON, once per copy of the sheet. Suggested
style: amber bg `#FDEFD8`, bold `#945A06` text, `#F59E0B` 2px border, height
~42px. Place it near the dropdown range so users see it before editing.
If the tab has `frozenColumnCount > 0`, painting bg+borders across cells
(no merge) plus `OVERFLOW_CELL` on the text cell is a working substitute
for merge — direct merges across the freeze return HTTP 400.

Re-check Sheets API release notes quarterly; once the toggle is API-exposed,
drop the banner and set the field programmatically.
