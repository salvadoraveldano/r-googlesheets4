# Reading Data

**Batching rule (read side):** one batched range read per tab or block — `read_sheet()`/`range_read()` with an explicit range, `range_speedread()`, or `read_values()` (`gs_helpers.R`) for several ranges at once. **Never loop per-cell or per-row reads**: they are orders of magnitude slower, burn straight through the read quota, and long QA scripts built that way get killed before finishing.

## Standard read

```r
# By URL
df <- read_sheet("https://docs.google.com/spreadsheets/d/SHEET_ID/")

# By ID
df <- read_sheet("SHEET_ID_OR_URL")

# Specific tab + range
df <- read_sheet(ss, sheet = "Data",  range = "A:V")
df <- read_sheet(ss, sheet = "Data",  range = "A3:V600")

# With column type specification (one char per column)
df <- read_sheet(ss, col_types = "ccnnd")
# c = character, n = numeric, d = date
```

## Fast CSV-style read

For large sheets, `range_speedread()` bypasses the Sheets API and reads via
the CSV export endpoint. Much faster for 10K+ rows.

```r
df <- range_speedread(ss, sheet = "Data")
```

Caveats: doesn't honor cell-level formatting; treats everything as text
unless you re-coerce; respects only the `range` you pass.

## Cell-level read (with formatting metadata)

When you need the format payload (colors, fonts, borders) — for example
to regenerate a tab — read at the cell level:

```r
cells <- range_read_cells(ss, sheet = "Data", range = "A1:F20",
                          cell_data = "full")
# Returns tibble: row, col, loc (A1-style), cell (list-column with full CellData)

# A single cell's full payload
str(cells$cell[[1]])
```

For comprehensive dumps including `effectiveFormat`, merges, conditional
formats — use `dump_reference_tab()` from `scripts/gs_qa.R`. See
[qa-pre-build-dump.md](qa-pre-build-dump.md).

## Error-resilient read

When iterating over many tabs / ranges that may not exist:

```r
df <- tryCatch(
  read_sheet(ss, sheet = tab_name, range = range_spec),
  error = function(e) {
    message(sprintf("Failed to read %s: %s", tab_name, e$message))
    tibble::tibble()
  }
)
```

## NA traps & parsing when filtering source data

Empty source cells come back as `NA`, and two R quirks then bite hard:

- **`nzchar(NA)` is `TRUE`** and **`NA != "x"` is `NA`** — so a predicate like
  `nzchar(cat) & cat != "#N/A"` lets `NA`-category rows THROUGH, and the `NA`
  later crashes `if(...)` ("missing value where TRUE/FALSE needed") or silently
  corrupts a join/aggregate.

```r
# WRONG — NA rows survive, then blow up downstream
keep <- nzchar(d$cat) & d$cat != "#N/A"
# RIGHT — !is.na() FIRST; R short-circuits FALSE & NA -> FALSE
keep <- !is.na(d$cat) & nzchar(d$cat) & d$cat != "#N/A"
```

- **`read_sheet()` can drop entirely-empty LEADING/TRAILING columns**, shifting
  positional indices (`d[[7]]` is no longer source col G). When position
  matters, read an explicit A1 range and assert the shape, or read by absolute
  column via REST `spreadsheets.values.get`.

```r
stopifnot(ncol(d) == 18L)              # or: all(expected_names %in% names(d))
# The full positional-read arg bundle — grid stays cell-for-cell faithful:
grid <- range_read(ss, sheet = "Data", range = "A1:AZ1200",
                   col_names = FALSE, col_types = "c",
                   trim_ws = FALSE, .name_repair = "minimal")
```

- **Numbers read back as text** (`$`, commas, `%`, accounting) → use
  `parse_num()` from `gs_qa.R` (`as.numeric(gsub("[^0-9.-]", "", x))`).
  `as.numeric(gsub("[, ]", "", x))` returns `NA` on a leading `$`. Accounting
  parentheses `(100)` lose their sign — normalize `()`→`-` first if present.
  For anything numeric-critical, skip the string-parsing entirely and use the
  UNFORMATTED_VALUE read below.

## Unformatted read for numeric work (reconciliation-grade)

Every read above returns what the cell **displays**, so number formats leak into
the data (`"$1,234.56"`, `"(123)"`, `"5%"`) and `as.numeric()` fails or — worse —
a `col_types = "c"` read silently zeroes comma-formatted amounts downstream.
When the numbers must be *right* (totals tie-outs, recon vs raw data), read
through the REST API with `valueRenderOption = "UNFORMATTED_VALUE"` — numbers
arrive as numbers, dates as serials, and no parsing step exists to get wrong:

```r
v <- read_values(ss, c(totals = "'P&L Q1'!B2:E40", check = "Checks!D4"),
                 value_render = "UNFORMATTED_VALUE")
v$totals[3, 2]        # numeric matrix: numbers are numbers, dates are serials
v$check               # 1 x 1 matrix
```

`read_values(ss, ranges, value_render = "FORMATTED_VALUE")` (in `gs_helpers.R`)
makes one `values.get` call per range and returns a **named list of matrices**
(names = the ranges, or `names(ranges)` if you named them):

- A matrix is **numeric** when every non-blank cell is a number, otherwise
  **character** (numbers written in plain notation, never `1e+06`). Ragged
  rows are padded (`NA` in a numeric matrix, `""` in a character one); a range
  with no values gives a 0 x 0 matrix.
- Pass the range as you would type it in Sheets, quoting tab names that need
  it (`"'P&L Q1'!A1:C10"`, `"'Joe''s Tab'!A1"`). The helper URL-encodes it,
  because it sits in the URL **path** (`values/{range}`): an unencoded range
  with a space, quote or `&` never reaches Google. This is the opposite of the
  `ranges=` *query* param of `spreadsheets.get`, which must stay raw (see
  `api-endpoints.md`).
- `request_make()` retries 429 and 500/502/503 with backoff (gargle 1.5.2; a 504
  is not retried), so a quota burst slows the read down instead of failing it. A real error stops with the HTTP status
  and the range in the message.
- Dates come back as serial numbers (`dateTimeRenderOption = "SERIAL_NUMBER"`)
  under `"UNFORMATTED_VALUE"`; convert at the edge. `"FORMULA"` returns the
  formulas as text.

## Spreadsheet metadata

```r
meta <- gs4_get(ss)
meta$name             # spreadsheet title
meta$sheets           # tibble of sheet names, IDs, dimensions
sheet_names(ss)       # just the tab names (character vector)
sheet_properties(ss)  # detailed sheet-level metadata
```

`sheet_properties()` is what `get_sheet_id()` queries — it returns a tibble
with `name`, `index`, `id` (the numeric sheetId you need for batchUpdate),
and grid dimensions.

## Reading ranges across multiple sheets

Use `read_values()` with several ranges. It is one call per range, which is
what the API needs anyway.

```r
v <- read_values(ss, c("'P&L'!A1:Z100", "'OPEX'!A1:M50", "'Revenue'!A1:P30"))
v[["'OPEX'!A1:M50"]]            # character matrix, one entry per range
```

Do not hand a vector of ranges to `request_generate("...values.batchGet")`.
gargle's request builder takes scalar parameters only, so
`params = list(ranges = c(...))` fails with `values must be length 1` before
any request is sent.
