# Writing Data

Three core write functions in `googlesheets4`:

| Function          | Use case                                 | Behavior                                       |
|-------------------|------------------------------------------|------------------------------------------------|
| `sheet_write()`   | Overwrite an entire tab                  | Auto-styles header row, frozen, shrink-wraps   |
| `range_write()`   | Write a tibble starting at a specific cell | Writes data extent or exact rectangle        |
| `sheet_append()`  | Add rows to an existing tab              | Appends below the last data row                |

For many individual cells (formulas, labels, KPIs), use the **buffered**
pattern instead — see [buffered-writes.md](buffered-writes.md).

## `sheet_write()` — overwrite

```r
sheet_write(my_tibble, ss = ss, sheet = "Data")
write_sheet(my_tibble, ss = ss, sheet = "Data")  # alias

# Creates the tab if it doesn't exist
sheet_write(my_tibble, ss = ss, sheet = "NewTab")
```

Side effects: header row is bolded and frozen, sheet dimensions shrink to
fit the data, existing content (and formatting!) is wiped.

## `range_write()` — targeted write

```r
# Starting at a cell — data extent determines the rectangle
range_write(ss, data = my_tibble, sheet = "Data", range = "B5")

# Exact rectangle — WARNING: unoccupied cells in the range get cleared!
range_write(ss, data = my_tibble, sheet = "Data", range = "B5:D10")

# Without column names
range_write(ss, data = my_tibble, sheet = "Data", range = "A2", col_names = FALSE)

# Preserve existing formatting (default reformat=TRUE clears it!)
range_write(ss, data = my_tibble, sheet = "Data", range = "A1", reformat = FALSE)
```

### ⚠️ The `reformat = TRUE` trap

`range_write()` defaults to `reformat = TRUE`, which **clears all existing
formatting** in the target range — fonts, colors, borders, number formats,
all gone. When updating values in a pre-styled sheet, **always** pass
`reformat = FALSE`:

```r
range_write(ss, data = updated_values,
            sheet = "Cover", range = "B5",
            col_names = FALSE,
            reformat = FALSE)   # ← keep the existing formatting
```

## `sheet_append()` — append rows

```r
sheet_append(ss, data = new_rows, sheet = "Log")
```

Appends below the last non-empty row. Headers must already match.

### Idempotent append (upsert)

`sheet_append()` is a blind append — re-running the same script duplicates
every row, which silently corrupts log/ledger tabs. Make re-runs safe by
appending only the delta on a key column:

```r
existing <- read_sheet(ss, sheet = "Log")
delta    <- dplyr::anti_join(new_rows, existing, by = "txn_id")   # needs the dplyr package; the skill itself does not
if (nrow(delta) > 0) sheet_append(ss, data = delta, sheet = "Log")
```

(To *update* matched rows instead, `range_write()` the matched range with
`reformat = FALSE` — same idempotent-rebuild discipline as merges and
conditional rules.)

## `range_flood()` / `range_clear()` / `gs_clear_values()`

```r
# Fill a range with a single value
range_flood(ss, sheet = "Data", range = "A1:F1", cell = "HEADER")

# Clear values AND formatting (reformat = TRUE is the default)
range_clear(ss, sheet = "Data", range = "A1:F20")

# Clear values only, keep formatting
range_clear(ss, sheet = "Data", range = "A1:F20", reformat = FALSE)
```

### ⚠️ `range_clear()` wipes formatting by default

`range_clear()` and `range_flood()` default to `reformat = TRUE`, the same trap
as `range_write()`: number formats, fills, fonts and borders in the range are
gone. A live check showed data validation and notes surviving, but the number
format and fill did not. To blank inputs and keep the look, use
`gs_clear_values()` (`gs_qa.R`, after `gs_helpers.R`), which has no `reformat`
to forget:

```r
gs_clear_values(ss, "Inputs")             # every value on the tab
gs_clear_values(ss, "Inputs!B2:B20")      # one range
```

It is one `values.clear` call: values go, while number formats, fills, data
validation and notes stay. The tab is always part of the range, so it cannot
touch another tab. A bare name is a whole tab (quoted for you, so a tab called
`Q1` is not read as cell Q1), a string with `!` is used as given (quote a name
with spaces yourself: `"'My Tab'!B2:B20"`), and a bare `"A1:F20"` is refused
with HTTP 400 instead of clearing the first tab.

## ⚠️ Writing dates & datetimes — the timezone trap

`Date` columns are safe. `POSIXct` columns are not: they are converted to
sheet serials **in the spreadsheet's timeZone** (a spreadsheet property, set
at creation — default depends on the creating account, often `Etc/GMT`). If
the R session's timezone differs, every datetime silently shifts by the
offset — no error, no warning, and a read-back into the same session
round-trips cleanly so the shift is invisible until a human compares clocks.

Two reliable patterns:

```r
# 1. Pin the sheet's timezone to the session's at creation
ss <- gs4_create("Report", timeZone = Sys.timezone())

# 2. Or sidestep serials entirely: write ISO strings + a DATE number format
write_cell(ss, "Log", r, c, format(ts, "%Y-%m-%d %H:%M"))
# then fmt_cells(..., numfmt_type = "DATE_TIME") if you need sheet-side math
```

For *display* formatting of date cells see
[number-formats.md](number-formats.md); for locale-proof date *labels* use
`safe_locale_date()` (`gs_qa.R`).

## Writing formulas with `gs4_formula()`

Mark strings as formulas (not plain text) so Sheets parses them as
expressions. Without `gs4_formula()`, a string starting with `=` lands
in the cell as literal text.

```r
formulas <- tibble(
  metric = c("Total", "Average", "Max"),
  value  = gs4_formula(c("=SUM(B2:B100)", "=AVERAGE(B2:B100)", "=MAX(B2:B100)"))
)
range_write(ss, data = formulas, sheet = "Summary", range = "A1")

# Cross-sheet SUMIFS
sumifs <- gs4_formula('=SUMIFS(People!C:C,People!A:A,"Technology")')
range_write(ss, data = tibble(val = sumifs),
            sheet = "Dept", range = "B5",
            col_names = FALSE, reformat = FALSE)

# Safe division (avoid #DIV/0!)
margin <- gs4_formula('=IF(B5=0,"",B10/B5)')

# Sheets-only: SPARKLINE
sparkline <- gs4_formula('=SPARKLINE(B2:M2, {"color","#2457C5"})')  # brand blue
```

### ⚠️ A formula needs a leading `=` — and the buffered path is the mirror image

Two symmetric traps depending on the write path:

- **`range_write(data = tibble(...))`** uses `RAW` by default — a string
  `"=SUM(...)"` lands as literal **text** unless wrapped in `gs4_formula()`
  (above).
- **`write_cell()` → `flush_writes()`** flushes with `USER_ENTERED`, so a
  leading-`=` string IS parsed as a formula — but a string written **without**
  the `=` is stored as **text**: the cell shows the formula source and
  `SUM`/math silently treat it as 0. This bites when building cross-sheet refs
  programmatically:

```r
# WRONG — stored as text "'Source'!B11"; a SUM over the column ignores it
write_cell(ss, "Direct", r, c, sprintf("'%s'!B11", src_tab))
# RIGHT — leading '=' makes it a live formula
write_cell(ss, "Direct", r, c, sprintf("='%s'!B11", src_tab))
```

Note `fraw()` deliberately *strips* `=` to concatenate inner builders — the
FINAL written string must still begin with `=`. Verify by reading the cell
back: it should return the evaluated value, not the formula text.

For programmatic formula construction (SUMIFS with dynamic criteria), use
the builders in `gs_formulas.R`. See [formulas.md](formulas.md).

## Writing many individual cells (use the buffer)

Don't loop `range_write()` over individual cells — each call is one API
request. Use `write_cell()` + `flush_writes()` from `gs_buffer.R`:

```r
source("scripts/gs_buffer.R")

write_cell(ss, "P&L", 5, 3, "  Gross Profit")
write_cell(ss, "P&L", 5, 6, '=SUMIFS(Revenue!P:P,Revenue!B:B,$C$1)')
write_cell(ss, "P&L", 6, 3, "  Total OPEX")
# … hundreds more …

flush_writes(ss)   # ONE API call for all of them
```

See [buffered-writes.md](buffered-writes.md) for the full pattern.
