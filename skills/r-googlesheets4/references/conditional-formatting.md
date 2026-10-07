# Conditional Formatting

Two helpers in `gs_helpers.R`:

```r
fmt_cond_negative(sid, 2, 20, 2, 4, color = COL_RED_TEXT)
fmt_cond_color_scale(sid, 2, 20, 5, 5,
                     min_color = COL_GREEN_LIGHT,
                     mid_color = COL_YELLOW_LIGHT,
                     max_color = COL_RED_LIGHT)
```

## Boolean rule (highlight by condition)

```r
list(addConditionalFormatRule = list(
  rule = list(
    ranges = list(grid_range(sid, 2, 20, 2, 4)),
    booleanRule = list(
      condition = list(
        type   = "NUMBER_LESS",
        values = list(list(userEnteredValue = "0"))
      ),
      format = list(
        textFormat = list(foregroundColorStyle = list(rgbColor = COL_RED_TEXT))
      )
    )
  ),
  index = 0L   # rule priority within the sheet
))
```

Common condition types:

| Type                   | Values needed                                |
|------------------------|----------------------------------------------|
| `NUMBER_GREATER`       | one value                                    |
| `NUMBER_LESS`          | one value                                    |
| `NUMBER_BETWEEN`       | two values                                   |
| `NUMBER_EQ`            | one value                                    |
| `NUMBER_NOT_EQ`        | one value                                    |
| `TEXT_CONTAINS`        | one value                                    |
| `TEXT_STARTS_WITH`     | one value                                    |
| `BLANK` / `NOT_BLANK`  | none                                         |
| `DATE_AFTER`           | one value (`"2026-04-30"` or relative)       |
| `CUSTOM_FORMULA`       | one — `=$A2 > $B2`                            |

## Gradient (color scale)

```r
list(addConditionalFormatRule = list(
  rule = list(
    ranges = list(grid_range(sid, 2, 20, 5, 5)),
    gradientRule = list(
      minpoint = list(color = COL_GREEN_LIGHT,  type = "MIN"),
      midpoint = list(color = COL_YELLOW_LIGHT, type = "PERCENTILE", value = "50"),
      maxpoint = list(color = COL_RED_LIGHT,    type = "MAX")
    )
  ),
  index = 0L
))
```

`type` ∈ `MIN` / `MAX` / `NUMBER` / `PERCENT` / `PERCENTILE`. Use
`PERCENTILE` for the midpoint when the data range is unknown.

## ⚠️ Idempotent re-runs (rule stacking)

`addConditionalFormatRule` **appends**. Re-running a script without
clearing first stacks duplicate rules — five re-runs = five copies of
the same rule.

The correct pattern: count existing rules, delete exactly that many
(descending so indices stay stable), then add fresh ones.

```r
# Clean wipe + fresh add
all_fmt <- c(
  fmt_delete_cond_rules(as.character(ss), sid),   # first arg is the ID string
  list(fmt_cond_negative(sid, 12, 200, 2, 25))
)
batch_format(ss, all_fmt)
```

`fmt_delete_cond_rules()` (in `gs_qa.R`) calls `count_cond_rules()` first,
so it knows the actual rule count and deletes exactly that many.

**Never blind-delete a fixed range of indices.** `deleteConditionalFormatRule`
errors HTTP 400 on a missing index ("No conditional format on sheet at
index N"), and because batchUpdate is atomic, one bad delete aborts every
other request in the same batch.

**Why descending order matters:** within a single batchUpdate the deletes
are applied in order. Deleting index 0 shifts every later rule's index
down by 1, so iterating ascending deletes the wrong rules. Deleting from
highest to lowest keeps remaining indices stable.

```r
# Inside fmt_delete_cond_rules:
lapply(seq.int(n, 1L), function(i)
  list(deleteConditionalFormatRule = list(sheetId = sheet_id, index = i - 1L)))
```
