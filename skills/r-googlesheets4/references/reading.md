# Reading Data

**Batching rule (read side):** one batched range read per tab or block — `read_sheet()`/`range_read()` with an explicit range, `range_speedread()`, or `values.batchGet` for many ranges in one call. **Never loop per-cell or per-row reads**: they are orders of magnitude slower, burn straight through the read quota, and long QA scripts built that way get killed before finishing.

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
rest_values <- function(ss_id, tab, rng) {
  gargle::response_process(gargle::request_make(gargle::request_build(
    method = "GET",
    path = "v4/spreadsheets/{spreadsheetId}/values/{range}",
    params = list(spreadsheetId = ss_id,
                  range = utils::URLencode(paste0("'", tab, "'!", rng), reserved = TRUE),
                  valueRenderOption = "UNFORMATTED_VALUE",
                  dateTimeRenderOption = "SERIAL_NUMBER"),
    base_url = "https://sheets.googleapis.com",
    token = googlesheets4::gs4_token())))$values
}
```

Notes:
- The range is interpolated into the URL **path** (`values/{range}`), so it
  **must** be `URLencode(..., reserved = TRUE)`-encoded here — unlike the
  `ranges=` *query* param of `spreadsheets.get`, which must stay raw
  (see `api-endpoints.md`).
- `dateTimeRenderOption = "SERIAL_NUMBER"` keeps dates as spreadsheet serials —
  ideal when your comparison logic also works in serials; convert at the edge.
- `$values` is a nested list; rows are ragged (trailing empties dropped per row).

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

Use `values.batchGet` (one API call) for many ranges at once:

```r
req <- request_generate(
  endpoint = "sheets.spreadsheets.values.batchGet",
  params = list(
    spreadsheetId = as.character(ss),
    ranges = c("'P&L'!A1:Z100", "'OPEX'!A1:M50", "'Revenue'!A1:P30")
  )
)
resp <- request_make(req)
body <- httr::content(resp, as = "parsed")
# body$valueRanges[[1]]$values, body$valueRanges[[2]]$values, …
```
