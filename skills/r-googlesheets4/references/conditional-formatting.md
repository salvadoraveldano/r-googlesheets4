# Conditional Formatting

Helpers in `gs_helpers.R`. Each returns ONE `addConditionalFormatRule` request
for `batch_format()`:

```r
fmt_cond_negative(sid, 2, 20, 2, 4)                      # COL_NEGATIVE text (BB2D27)
fmt_cond_color_scale(sid, 2, 20, 5, 5)                   # SCALE_DIV: blue (low, good) -> white -> red (high, bad)
do.call(fmt_cond_color_scale, c(list(sid, 2, 20, 6, 6), SCALE_HEAT))   # white -> amber -> red

# Boolean rules: set any of bg_color / font_color / bold (at least one)
fmt_cond_formula(sid, 4, 200, 1, 9, '=$H4="Overdue"',          # CUSTOM_FORMULA
                 bg_color = STATUS$negative$fill, font_color = STATUS$negative$ink)
fmt_cond_text_equals(sid, 4, 200, 8, 8, "Blocked", bg_color = STATUS$negative$fill,
                     font_color = STATUS$negative$ink)          # TEXT_EQ
fmt_cond_text(sid, 4, 200, 3, 3, op = "contains", text = "late",
              bg_color = STATUS$warning$fill, font_color = STATUS$warning$ink)
# op: "equals" "starts_with" "contains" "not_contains" (pass `text` by name)
fmt_cond_number(sid, 4, 200, 11, 11, 0.9, op = "greater", font_color = COL_NEGATIVE)
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

## Status colours

Status is the only use of red, green and amber, and it goes only on the rows
at risk: a "fine" state stays plain grey text. Each state in `STATUS` is a
pair plus a mark:

| State | `$fill` | `$ink` | `$mark` |
|---|---|---|---|
| positive | E3F2E8 | 17603A | 1F7A47 (`COL_POSITIVE`) |
| negative | FBE9E7 | 9B2420 | BB2D27 (`COL_NEGATIVE`) |
| warning | FCF0D9 | 7A4A00 | B8740A (`COL_WARNING`, bars and lines only) |
| info | E3F1F3 | 0D5562 | 16788A (`COL_INFO`) |
| neutral | EFEFEF | 3D3D3D | 8C8C8C |

A chip or a row highlight uses `$fill` with `$ink` on it (6.5:1 or more). A
coloured number with no fill (a delta) uses `$mark`. `fmt_status()` in
`gs_buffer.R` writes the chip rules for you, one per state, first listed wins:

```r
fmt_status(sid, 4, 200, 8, 8, c(Blocked = "negative", "At risk" = "warning"))   # "On track" stays grey
fmt_status(sid, 3, 3, 4, 4, c("✓" = "positive", "✕" = "negative"), op = "starts_with")   # one-cell badge
```

The old names still work and now hold the new values: `COL_RED_LIGHT` =
`STATUS$negative$fill`, `COL_GREEN_LIGHT` = `STATUS$positive$fill`,
`COL_YELLOW_LIGHT` = `STATUS$warning$fill`, `COL_RED_TEXT` = `COL_NEGATIVE`,
`COL_GRAY_TEXT` = `COL_TEXT_3` (666666). Give each fill its own state's ink.

**Scales** (in `fmt_cond_color_scale()`'s argument shape, so `do.call()` them):
`SCALE_DIV` (blue → white → red, the default: good low, bad high),
`SCALE_HEAT` (white → amber → red: higher is worse) and `SCALE_SEQ` (white →
accent; never on a tab with inputs, where blue means "type here"). Keep the
text in scaled cells in ink.

## Rule priority (`index`)

Every helper, `fmt_cond_color_scale()` included, takes a trailing `index`
(default `0L`). The rule is **inserted at that position** and the first matching
rule wins per cell, so with the default each rule added later in one batch lands
ABOVE the earlier ones. For "first listed wins", number them in listing order:

```r
rules <- list(
  fmt_cond_formula(sid, 4, 200, 1, 9, '=$H4="Overdue"', bg_color = STATUS$negative$fill, index = 0L),
  fmt_cond_number (sid, 4, 200, 11, 11, 0.9, "greater", bg_color = STATUS$warning$fill, index = 1L),
  fmt_cond_formula(sid, 4, 200, 1, 9, '=$B4=$C$1', bg_color = COL_RAISED, bold = TRUE, index = 2L))   # the picked row
batch_format(ss, rules, strict = TRUE)
```

`new_batch()` does the numbering for you. Its `$cf(f, sheet_id, ...)` calls any
`fmt_cond_*` helper as `f(sheet_id, ..., index = k)`, where `k` counts the rules
added through `$cf` for that `sheet_id`, starting at 0. So the rule you list
first wins, and you never type an `index`:

```r
b <- new_batch()
b$push(fmt_cells(sid, 1, 1, 1, 9, bold = TRUE))                      # any other request
b$cf(fmt_cond_formula, sid, 4, 200, 1, 9, '=$H4="Overdue"', bg_color = STATUS$negative$fill) # index 0
b$cf(fmt_cond_number,  sid, 4, 200, 11, 11, 0.9, "greater", bg_color = STATUS$warning$fill) # index 1
b$cf(fmt_cond_negative, sid, 4, 200, 2, 4)                                              # index 2
batch_format(ss, b$get(), strict = TRUE)
```

The count is per `sheet_id` because rule priority is per tab, so one collector can
hold the rules of several tabs. Use it for one build per `batch_format()` call.
Add every conditional-format rule through `$cf`: a rule pushed with `$push` is not
counted, uses the helpers' default `index = 0`, and where it ends up depends on
when it was pushed (checked live: it can reorder the `$cf` rules). Rules already on
the tab end up below the new ones (clear them first, as in the re-run section
below). Do not pass `index` to `$cf` yourself.

## ⚠️ A custom formula cannot point at another tab by name

A `CUSTOM_FORMULA` rule is rejected with HTTP 400 `Invalid
ConditionValue.userEnteredValue` when it references a **named range that lives
on another tab** (`=A1>NR_LIMIT`), and also when it uses a plain cross-tab ref
(`=A1>Data!$B$10`). Two forms work (checked live):

```r
# 1. Echo the value into a same-tab cell, point the rule at that cell
#    (Zero!C1 holds  =NR_LIMIT  or  =Data!$B$10)
fmt_cond_formula(sid, 1, 3, 1, 1, "=A1>$C$1", font_color = COL_NEGATIVE)
# 2. INDIRECT with a text address
fmt_cond_formula(sid, 1, 3, 1, 1, '=A1>INDIRECT("Data!B10")', font_color = COL_NEGATIVE)
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
        textFormat = list(foregroundColorStyle = list(rgbColor = COL_NEGATIVE))
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
      minpoint = list(color = SCALE_DIV$min_color, type = "MIN"),
      midpoint = list(color = SCALE_DIV$mid_color, type = "PERCENTILE", value = "50"),
      maxpoint = list(color = SCALE_DIV$max_color, type = "MAX")
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
