# Conditional Formatting

Helpers in `gs_helpers.R`. Each returns ONE `addConditionalFormatRule` request
for `batch_format()`:

```r
fmt_cond_negative(sid, 2, 20, 2, 4, color = COL_RED_TEXT)
fmt_cond_color_scale(sid, 2, 20, 5, 5,
                     min_color = COL_GREEN_LIGHT,
                     mid_color = COL_YELLOW_LIGHT,
                     max_color = COL_RED_LIGHT)

# Boolean rules: set any of bg_color / font_color / bold (at least one)
fmt_cond_formula(sid, 4, 200, 1, 9, '=$H4="Overdue"',          # CUSTOM_FORMULA
                 bg_color = COL_RED_LIGHT, font_color = COL_RED_TEXT, bold = TRUE)
fmt_cond_text_equals(sid, 4, 200, 8, 8, "Done", font_color = COL_GRAY_TEXT)   # TEXT_EQ
fmt_cond_text(sid, 4, 200, 3, 3, op = "contains", text = "late", bg_color = COL_RED_LIGHT)
# op: "equals" "starts_with" "contains" "not_contains" (pass `text` by name)
fmt_cond_number(sid, 4, 200, 11, 11, 0.9, op = "greater", bg_color = COL_RED_LIGHT)
# op: "greater" "less" "greater_eq" "less_eq"
```

`fmt_cond_text()` maps `op` to `TEXT_EQ` / `TEXT_STARTS_WITH` / `TEXT_CONTAINS` /
`TEXT_NOT_CONTAINS`, with the same `bg_color` / `font_color` / `bold` / `index`
arguments as the other boolean rules (`fmt_cond_text_equals()` is the `"equals"`
case and keeps working). The text match **ignores case**: checked live, a rule
for `"done"` highlights `Not done`, `DONE` and `Done early` for `contains`, and
`DONE` and `Done` for `equals`. A number matches on its displayed text
(`contains "1"` highlights `123`). `not_contains` also highlights EMPTY cells
(checked live), so keep its range to the rows that hold data.

`fmt_cond_formula()` takes the formula written for the **top-left cell** of the
range (`$` locks what must not shift) and it must start with `=`.

`fmt_cond_color_scale()` also takes a trailing `index` (default `0L`, as before),
so a gradient can sit at a chosen priority next to boolean rules:
`fmt_cond_color_scale(sid, 2, 20, 5, 5, index = 3L)`.

## Rule priority (`index`)

Every helper, `fmt_cond_color_scale()` included, takes a trailing `index`
(default `0L`). The rule is **inserted at that position** and the first matching
rule wins per cell, so with the default each rule added later in one batch lands
ABOVE the earlier ones. For "first listed wins", number them in listing order:

```r
rules <- list(
  fmt_cond_formula(sid, 4, 200, 1, 9, '=$H4="Overdue"', bg_color = COL_RED_LIGHT, index = 0L),
  fmt_cond_number (sid, 4, 200, 11, 11, 0.9, "greater", bg_color = COL_YELLOW_LIGHT, index = 1L),
  fmt_cond_formula(sid, 4, 200, 1, 9, '=MOD(ROW(),2)=0', bg_color = COL_LIGHT_GRAY,  index = 2L))
batch_format(ss, rules, strict = TRUE)
```

## ⚠️ A custom formula cannot point at another tab by name

A `CUSTOM_FORMULA` rule is rejected with HTTP 400 `Invalid
ConditionValue.userEnteredValue` when it references a **named range that lives
on another tab** (`=A1>NR_LIMIT`), and also when it uses a plain cross-tab ref
(`=A1>Data!$B$10`). Two forms work (checked live):

```r
# 1. Echo the value into a same-tab cell, point the rule at that cell
#    (Zero!C1 holds  =NR_LIMIT  or  =Data!$B$10)
fmt_cond_formula(sid, 1, 3, 1, 1, "=A1>$C$1", bg_color = COL_RED_LIGHT)
# 2. INDIRECT with a text address
fmt_cond_formula(sid, 1, 3, 1, 1, '=A1>INDIRECT("Data!B10")', bg_color = COL_RED_LIGHT)
```

Prefer the echo cell: it is plain cell references, so you can see and audit
it, while `INDIRECT` hides the dependency inside a text string. Hide or grey
the echo cell rather than deleting it.

## Boolean rule by hand (any condition type)

The helpers above cover the common types; the raw request is below.

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
(`gs_reset_tabs()` does the same for the tabs you name, together with charts, banding,
protections and the rest. See [creating-and-tabs.md](creating-and-tabs.md).)

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
