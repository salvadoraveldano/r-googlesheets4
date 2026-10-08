# Buffered Writes & Style Presets

The most efficient way to write many individual cells (formulas, labels,
KPIs at specific positions) is to **buffer** writes in memory and flush
them in ONE `values.batchUpdate`, then apply ALL formatting in ONE
`batchUpdate`. Two API calls total, no matter how many cells.

## The pattern

```r
source("scripts/gs_helpers.R")
source("scripts/gs_buffer.R")

# 1. Buffer all cell writes (no API calls yet)
write_cell(ss, "P&L", 1, 3, "Technology")
write_cell(ss, "P&L", 2, 3, '=$C$1 & " — FY2026 Budget Summary"')
write_cell(ss, "P&L", 5, 3, "  Gross Profit")
write_cell(ss, "P&L", 5, 6, '=SUMIFS(Revenue!P:P,Revenue!B:B,$C$1,Revenue!N:N,"6. Net revenue")')
# … hundreds more …

# 2. Flush ALL writes in ONE API call (USER_ENTERED — formulas evaluate).
#    strict = TRUE stops on an HTTP error instead of only logging it.
flush_writes(ss, strict = TRUE)

# 3. Apply ALL formatting in ONE batchUpdate
batch_format(ss, list(
  fmt_gridlines(sid, show = FALSE),
  fmt_merge(sid, 2, 2, 3, 8),
  apply_style(sid, 2, 2, 3, 8, STYLE_TITLE),
  # … all other formatting
))
```

**Result:** 2 API calls per tab, regardless of cell count. Critical for
staying under rate limits when building multi-tab reports.

## How the buffer works

`.wb` is a private environment with one slot, `.wb$data`, holding a list
of `{range, values}` entries (Sheets `ValueRange`s). `write_cell()` appends a
one-cell entry, `write_block()` appends a whole rectangle as ONE entry.
`flush_writes()` sends the whole list as a single
`values.batchUpdate` request.

```r
clear_writes()   # rare — abort a partial build without flushing
```

The buffer is process-scoped. If you build multiple sheets in one R
session, flush each sheet's buffer before starting the next.

### Strict flush, and what happens to the buffer on failure

By default `flush_writes()` only logs an HTTP error with `message()`, which
leaves empty tabs and scrolls by unnoticed (the same trap as `batch_format()`).
Build scripts should pass `strict = TRUE`: it `stop()`s on HTTP >= 400 and
the message carries Google's reason (for example
`Unable to parse range: 'NoSuchTab'!A1:A1` or `Range (...) exceeds grid limits`).

```r
flush_writes(ss, strict = TRUE)
```

Buffer state:

- **Google answered with an error status**: the buffer is cleared.
  `values.batchUpdate` is all-or-nothing, so none of that batch lands: checked
  live with a 400 (a good write queued next to a write to a tab that does not
  exist was not written either). `request_make()` already retries 429 and
  500/502/503 with backoff (gargle's `request_retry`; a 504 is not retried)
  before `flush_writes()` sees a status, so an error that reaches it is final
  for this call, and a 504 clears the buffer; re-sending the same buffer would
  not help. Fix the cause and queue the writes again. (A 429
  that outlasts the retries was not exercised.)
- **No answer at all (network error)**: the buffer is kept; call
  `flush_writes()` again (checked live by pointing the request at a dead proxy,
  then flushing again once it was removed).

## `write_block()` — a rectangle as one entry

```r
write_block(ss, sheet, row, col, x, as_text = FALSE)
```

`x` is a matrix or data.frame, written with its top-left cell at `(row, col)`.
A 2,000-cell table is one entry instead of 2,000. Column names are NOT written
(bind a header row yourself), `NA` cells become empty cells, and a plain vector
is written as one column. Every cell goes through the same rules as
`write_cell()` (below).

```r
write_block(ss, "Data", 1, 1, rbind(c("Item", "Qty", "Price")))   # a header row
write_block(ss, "Data", 2, 1, df)                                  # a data.frame keeps each column's type
```

Prefer a data.frame (or a numeric matrix) over `cbind()` of mixed types:
`cbind(c("a", "b"), c(1, 2))` turns the numbers into text, and text is parsed by
Sheets (next section) instead of being sent as numbers.

## What `write_cell()` and `write_block()` send

| You pass                              | Sent as                                   | Notes |
|---------------------------------------|-------------------------------------------|-------|
| R number (`2e6`, `0.1`, `1234L`)      | a JSON **number**                         | never `"2e+06"` text |
| `TRUE` / `FALSE`                      | a JSON boolean                            | |
| `NA`, `NaN`                           | `""` (empty cell)                         | `Inf` stops with an error |
| `"=SUM(A1:A3)"`                       | a formula                                 | USER_ENTERED evaluates it |
| `"plain text"`                        | text                                      | |
| `"+abc"`, `"-abc"`, `"@abc"`, `"'abc"`| text, with ONE `'` prefixed               | see below |
| `"-5"`, `"+5"`, `"-$5"`, `"-5%"`      | a number (a leading `+` is dropped)       | a string that is a signed number stays a number |
| any string with `as_text = TRUE`      | text, with `'` prefixed                   | for `"00123"`, `"1/2"`, `"TRUE"`, `"=A1"` kept as text |

**Why numbers are sent as numbers, not text.** `values.batchUpdate` with
`USER_ENTERED` parses text exactly as if it were typed. Checked live:
`as.character(2e6)` is `"2e+06"`, which Sheets parses and then displays with a
`2.00E+06` number format; and on a spreadsheet whose locale uses a decimal
comma (`de_DE`) the TEXT `"1234.5"` was stored as the number -243129 and
`"0.0025"` as 25, while the same values sent as JSON numbers stored 1234.5 and
0.0025. The helpers therefore never turn a number into text. If you
build a formula string around a number, format it yourself with
`format(x, scientific = FALSE, trim = TRUE)`.

**Why text starting with `+ - @ '` is prefixed.** Under `USER_ENTERED`, a
leading `+` makes the cell a formula (`"+abc"` became `#NAME?`, `"+"` became
`#ERROR!`), and a leading `'` is the Sheets "treat as text" marker, which is
swallowed (`"'abc"` was stored as `abc`). Both were reproduced live. A leading `-` or `@` was stored as plain text in the same test,
but Sheets' own UI reads them as formula starts, so they get the same prefix
(it costs nothing). Sheets removes ONE leading `'` and stores no prefix, so the
visible text is exactly what you passed (`"'abc"` shows as `'abc`).

To keep a string such as an ID with leading zeros, a fraction-looking code or
the word `TRUE` as text, pass `as_text = TRUE`:

```r
write_cell(ss, "IDs", 2, 1, "00123", as_text = TRUE)   # shows 00123, not 123
write_cell(ss, "IDs", 3, 1, "1/2",   as_text = TRUE)   # shows 1/2, not a date
```

The old idiom of typing your own leading `'` for this no longer works through
`write_cell()`: it is escaped like any other leading `'`, so `"'00123"` would
show `'00123`. Use `as_text = TRUE`.

A signed-number string such as a phone number (`"+15551234567"`) stays a number and loses
its `+`. Write phone numbers and IDs with `as_text = TRUE`.

A tab name containing `'` is escaped for you (`Bob's Tab` writes to
`'Bob''s Tab'!A1`).

## Style presets

`gs_buffer.R` ships reusable bundles. Apply with `apply_style()`:

```r
STYLE_BODY            # Arial 11, valign MIDDLE — apply globally first
STYLE_BODY_BOLD       # Arial 11 bold
STYLE_TITLE           # Arial 18 bold, halign LEFT
STYLE_SUBTITLE        # italic gray
STYLE_SECTION_HEADER  # white bold on black bg (override bg_color to brand blue, COL_BRAND)
STYLE_SUBTOTAL        # bold, light blue bg
STYLE_NET_INCOME      # 12pt bold, light blue bg
STYLE_REMAINING       # bold, light green bg
STYLE_GRAYED_OUT      # gray text on light gray bg
STYLE_PCT_ANNOTATION  # italic, muted gray
STYLE_TOTAL           # 11 bold, light gray bg
```

Brand-specific overrides (editable palette) are in
`brand.R`.

## `apply_style()` — preset + overrides

```r
apply_style <- function(sheet_id, start_row, end_row, start_col, end_col,
                        style, ...) { … }
```

`style` is a list of `fmt_cells` parameters; `...` overrides win. Passing an
override as `NULL` drops that property from the preset
(`apply_style(..., STYLE_SECTION_HEADER, bg_color = NULL)`).
`apply_style()` only forwards to `fmt_cells()`, so what a later call does to
properties set earlier is decided there: `fmt_cells()` masks each text
property on its own (`...textFormat.bold`, `.fontSize`, ...), so a later
`apply_style(..., font_size = 16)` keeps the bold, family and colour from an
earlier preset on those cells (checked live: a `STYLE_SECTION_HEADER` cell kept
white bold Arial after a following call set only size and italic).

```r
# Use preset as-is
apply_style(sid, 35, 35, 3, 6, STYLE_NET_INCOME)

# Override specific fields
apply_style(sid, 35, 35, 6, 6, STYLE_NET_INCOME,
            numfmt_type = "NUMBER", numfmt_pattern = '$#,##0;($#,##0);"-"')
```

## `write_section_header()` — buffered helper

Writes the label to the buffer AND returns the format requests (merge +
style + row height). Use with `c()` to flatten into your format list:

```r
all_fmt <- list()
all_fmt <- c(all_fmt, write_section_header(ss, sn, sid, 4,  "EXECUTIVE SUMMARY",
                                           bg_color = COL_BRAND))
all_fmt <- c(all_fmt, write_section_header(ss, sn, sid, 12, "P&L",
                                           bg_color = COL_BRAND))

# Buffer the rest of the cells…

flush_writes(ss, strict = TRUE)        # one call for ALL labels + formulas
batch_format(ss, all_fmt, strict = TRUE)   # one call for ALL formatting
```

Returns 3 requests per call — combine with `c()`, not `list()`.

## Layered styling — global default first

The `batchUpdate` API applies requests in order; later requests override
earlier ones for the same cells. Use that to layer:

```r
all_fmt <- c(
  list(
    # 1. Global defaults FIRST
    apply_style(sid, 1, last_row, 1, 8, STYLE_BODY),

    # 2. Hide gridlines, freeze
    fmt_gridlines(sid, show = FALSE),
    fmt_freeze(sid, rows = 4)
  ),

  # 3. Section-specific overrides (last writer wins)
  fmt_pnl_section(sid),
  fmt_revenue_section(sid),

  # 4. Emphasis borders LAST so they're not wiped by other border requests
  fmt_emphasis_borders(sid)
)
batch_format(ss, all_fmt)
```

## Timing tip

After a large `flush_writes()`, Sheets sometimes hasn't fully committed
the cell values when the immediately following `batch_format()` arrives,
causing intermittent issues on tabs with hundreds of cells.

```r
flush_writes(ss, strict = TRUE)
Sys.sleep(3)   # let Google's backend catch up
batch_format(ss, all_fmt)
```

3 seconds is enough in practice. Skip on small writes (< 50 cells).
