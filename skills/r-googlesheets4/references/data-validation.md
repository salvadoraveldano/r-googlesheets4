# Data Validation (Dropdowns, Number, Date, Custom)

## Dropdown from a list

```r
fmt_dropdown(sheet_id = sid,
             start_row = 2L, end_row = 100L,
             start_col = 3L, end_col = 3L,
             values = c("Fixed", "Variable", "SaaS"))
```

`strict = TRUE` (default in the helper) rejects values not in the list.
`showCustomUi = TRUE` shows the dropdown chevron. Add `input_message = "Pick one"`
(trailing argument, also on `fmt_dropdown_range()`) for the hint shown when a
cell is selected (`dataValidation.inputMessage`).

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

## Number, date, text and custom rules: `fmt_validation()`

Refuse the wrong kind of input in a cell, for example on the input cells of a
model, so text typed into one cannot cascade `#VALUE!` through the formulas:

```r
fmt_validation(sheet_id, start_row, end_row, start_col, end_col, type,
               values = NULL, input_message = NULL, strict = TRUE,
               show_custom_ui = NULL)

batch_format(ss, list(
  # Number from 0 to 1 (two values for the BETWEEN types)
  fmt_validation(sid, 5, 50, 3, 3, "NUMBER_BETWEEN", c(0, 1),
                 input_message = "A rate from 0 to 1."),
  # One value: 0 or more. Numbers, strings and Date objects all work.
  fmt_validation(sid, 5, 50, 4, 4, "NUMBER_GREATER_THAN_EQ", 0),
  # A real date, and one that falls before a limit
  fmt_validation(sid, 5, 50, 2, 2, "DATE_IS_VALID",
                 input_message = "Enter a date, for example 2026-03-14."),
  fmt_validation(sid, 5, 50, 6, 6, "DATE_BEFORE", as.Date("2030-01-01")),
  # Any formula, written for the TOP-LEFT cell; `$` locks what must not shift
  fmt_validation(sid, 5, 50, 7, 7, "CUSTOM_FORMULA", "=AND(ISNUMBER(G5),G5>0)"),
  # Warn but still accept the value
  fmt_validation(sid, 5, 50, 8, 8, "TEXT_CONTAINS", "@", strict = FALSE)),
  strict = TRUE)
```

| `type`                                                                        | `values`           |
|-------------------------------------------------------------------------------|--------------------|
| `NUMBER_BETWEEN`, `NUMBER_NOT_BETWEEN`, `DATE_BETWEEN`, `DATE_NOT_BETWEEN`    | two (`c(lo, hi)`)  |
| `NUMBER_GREATER`, `NUMBER_GREATER_THAN_EQ`, `NUMBER_LESS`, `NUMBER_LESS_THAN_EQ`, `NUMBER_EQ`, `NUMBER_NOT_EQ` | one number |
| `DATE_BEFORE`, `DATE_AFTER`, `DATE_ON_OR_BEFORE`, `DATE_ON_OR_AFTER`, `DATE_EQ` | one date: `"2026-01-31"`, a `Date`, or a formula such as `"=TODAY()"` |
| `TEXT_CONTAINS`, `TEXT_NOT_CONTAINS`, `TEXT_EQ`                               | one string         |
| `CUSTOM_FORMULA`                                                              | one formula, starts with `=` |
| `DATE_IS_VALID`, `TEXT_IS_EMAIL`, `TEXT_IS_URL`                               | none               |

A wrong `type`, the wrong number of values or a formula without `=` stops with
an error before anything is sent. `strict = FALSE` shows a warning instead of
rejecting. `show_custom_ui` is left out unless you set it: it matters only for
list rules. Rules were checked live: the type, values (dates as `yyyy-mm-dd`),
input message and strictness read back as written.

> **⚠ API writes BYPASS validation.** A rule only guards what a person types in
> the Sheets UI. Anything written through the API (`values.update`,
> `write_block()` + `flush_writes()`, `range_write()`) goes straight in, even when it breaks the
> rule: checked live, `"abc"` written to a `NUMBER_BETWEEN 0..1` cell stays there
> and the rule stays on the cell. So a validation rule never proves that a sheet
> your script filled is clean. Check what you wrote with `read_values()`, and use
> formulas (`ISNUMBER`, a check column) for anything that must hold.

## Other types — checkbox

`BOOLEAN` renders an **interactive checkbox** in the cell (the TRUE/FALSE
cell value drives its state — write `TRUE`/`FALSE` to pre-set it). No helper;
the raw request is short:

```r
list(setDataValidation = list(
  range = grid_range(sid, 2L, 100L, 5L, 5L),   # E2:E100
  rule  = list(condition = list(type = "BOOLEAN"))
))
```

Picklists are `fmt_dropdown()` / `fmt_dropdown_range()` (above). Any other
condition type goes in a raw `setDataValidation` request of the same shape.

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
| Number / date / text / formula rule, or `strict = FALSE` | `fmt_validation()` (above). A picklist with `strict = FALSE`: build inline, `fmt_dropdown()` is always `strict = TRUE` |

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
