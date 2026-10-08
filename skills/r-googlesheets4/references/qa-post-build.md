# Post-Build QA — verify the rendered view, not just the cells

When you finish a build, the temptation is to query a few cells, see
the values you expected, and declare done. That misses an entire class
of failures: cells that contain the right value but are not visible to
the user.

Real bugs caught by this checklist:

- Title text written to `A1`. Verified `A1 == "TITLE TEXT"`. But col A
  was `hiddenByUser = TRUE` (carried over from `sheet_copy()` of a
  source tab that hid `A:B`). User saw an empty navy bar.
- KPI tile merged `B4:C4`. Merge confirmed; label confirmed. But B was
  hidden and C was 30 px wide. User saw the tail `"ING"` of `"CLOSING"`.
- Section labels in column C. Labels confirmed. But C was 30 px wide
  (set as a "narrow gutter" in column-widths). User saw `Liqu`, `Sale`,
  `Tota`.
- After `sheet_copy()` + `insertDimension(7 rows at top)`, the source
  tab's row-1 banner (`"Revenue Report | …"`) shifted to row 8 —
  directly under the new exec band. Looked like a UI bug.
- Subtitle date `"%B %d, %Y"` rendered as `"abril 24, 2030"` because
  `LC_TIME` was Spanish on the dev box.

The common thread: **content correctness was checked, rendered view
was not.**

## The checklist

After every build, run these in order:

### 1. Find the first visible column. Anchor user-facing content there.

```r
anchor_col <- first_visible_col(SS_ID, sid)
write_cell(ss, TAB, R_TITLE, anchor_col, TITLE_TEXT)   # not column 1
```

Don't assume A1 is visible — `sheet_copy()` carries over `hiddenByUser`.

### 2. For each merged range with visible content, audit visible width.

```r
ok <- audit_merge(SS_ID, sid, start_col = 2L, end_col = 4L,
                  min_visible_px = 80L)
stopifnot(ok)
```

A merge across a hidden col plus a 30 px gutter renders as 30 px.

### 3. After `sheet_copy()` + `insertDimension`, audit shifted rows.

```r
# Read the rows that just shifted into your "spacer" zone
content <- range_read(ss, sheet = TAB, range = "A8:Y10",
                      col_types = "c", .name_repair = "minimal")
# If non-empty, explicitly clear or restyle before declaring done
```

### 4. Force English-locale dates.

R's `format(Sys.Date(), "%B")` honors `LC_TIME`. On a non-US machine it
flips to local language. Use `safe_locale_date()` from `gs_qa.R`:

```r
today_str <- safe_locale_date(Sys.Date(), "%B %d, %Y")
```

### 5. For every `write_cell(...)` call, ask: would a user see this?

Three things break visibility:
- The column is hidden (`hiddenByUser = TRUE`).
- The row is hidden.
- The cell is covered by a merge with a different top-left anchor.

For systematic auditing of step 5, query columnMetadata for every col
you wrote to and assert `hiddenByUser` is `FALSE`.

### 6. For every chart added, audit source-range columns.

```r
audit_chart_sources(SS_ID)        # default: every tab, so cross-tab dashboards are covered
audit_chart_sources(SS_ID, sid)   # optional 2nd argument narrows it to the charts on ONE tab
```

Use the one-argument form after a build. Passing the dashboard tab's id as the
second argument skips the charts that sit on other tabs.

Each domain and series is checked against the hidden columns of the tab it
READS FROM, so the all-tabs form covers cross-tab dashboards. The audit catches
most cases, not a partial series loss (Sheets then returns fewer series than the
chart holds): compare the series count you read back with the number you built.

Sheets silently falls back to the empty-state placeholder
(`"Add a series to start visualizing your data"`) when a chart's
`sourceRange` references columns where `hiddenByUser = TRUE` — even if
the underlying cells contain valid formula values. The chart object is
created, the data is in the cells, the API returns 200 OK. Reading back
the cells alone will not catch this.

## The render-vs-cell distinction

| Check                              | Catches                                    |
|------------------------------------|--------------------------------------------|
| `read_sheet(ss, range = "A1")`     | Wrong content                              |
| `range_read_cells(...)`            | Wrong content + format on the cell itself  |
| Open the URL in a browser          | Hidden cols, narrow widths, locale-bugs    |
| `audit_chart_sources()`            | Charts hidden behind hidden cols           |
| `first_visible_col()`              | Anchor content placed in hidden col        |
| `audit_merge()`                    | Merges with insufficient visible width     |
| `dump_reference_tab()` + diff      | Format-contract drift                      |
| `gs_count_objects()` before / after a rebuild | Objects stacked or lost (charts, rules, validation, notes, ...) |

## Concrete one-liner audit script to run after every build

```r
ss_id  <- as.character(ss)
sid    <- get_sheet_id(ss, TAB)
audit_chart_sources(ss_id)                       # every tab
stopifnot(first_visible_col(ss_id, sid) <= 1L)   # title col is visible
stopifnot(audit_merge(ss_id, sid, 3L, 8L, 100L)) # title merge has space
cat("[QA] post-build checks passed\n")
```

If you can't visually inspect the rendered page (CI, headless), at least
run these. The cost is one more API call; the saving is iter-day rebuilds.

For the full render-and-score visual pass (layout audit, PDF pages,
rubric, severity triage, fix-at-source loop) run `visual_qa()` from
`gs_visual_qa.R` and follow [visual-review-rubric.md](visual-review-rubric.md);
this file covers the cell-level audits that complement it.

## Export a tab to PDF for offline visual inspection

To look at the rendered page, pull a PDF straight from the Drive
export endpoint with the active `googlesheets4` token — then open / `Read()`
the PDF. `export_sheet_as_pdf()` in `gs_qa.R` wraps it:

```r
export_sheet_as_pdf(ss, "Summary", "/tmp/qa_direct.pdf")
# then inspect the PDF (Read tool, or any viewer)
```

Under the hood it GETs
`https://docs.google.com/spreadsheets/d/<ID>/export?format=pdf&gid=<GID>&…`
with `gs4_token()` and `write_disk()`. This is the highest-leverage check
for **render-only** defects a cell read-back can't catch — e.g. a formula
stored as text (shows the formula string), clipped/merged banners, or a
column that's narrower than its content. Pair it with the cell-level audits
above: reads prove the values, the PDF proves the rendering.

Two gotchas on this endpoint:

- **`gs4_token()` is already an httr config object** — pass it directly as an
  argument to `httr::GET(url, gs4_token(), ...)`. Do **not** wrap it in
  `httr::config()` or rebuild it into `add_headers()`; re-wrapping breaks the
  auth handshake.
- **The export endpoint rate-limits bursts (HTTP 429)** — and gargle's
  automatic 429 retry does NOT apply here (it only covers v4 API calls made
  through `request_make()`; this is a bare `httr::GET`). `export_sheet_as_pdf()`
  retries with linear backoff (5 tries, `Sys.sleep(15 * try_i)`). When exporting
  many tabs in a loop, also sleep ~10s between tabs to stay under the burst limit.

## Count the objects around a rebuild

A rebuild in place can stack charts and rules or lose a validation without any
error. `gs_count_objects()` (in `gs_qa.R`) takes a census with ONE read-only
`spreadsheets.get`: per tab, the charts, conditional rules, cells with a
validation rule, protected ranges, filter views, slicers, banded ranges, merges,
cells with a note and frozen rows and columns. Take it before the rebuild, take
it again after, and compare, the same idea as the flip-and-restore test below:

```r
before <- gs_count_objects(ss_id)
# ... rerun the build with SHEET_ID=<id> ...
stopifnot(identical(before, gs_count_objects(ss_id)))   # same objects, none stacked or lost
```

When the two differ, `print()` both and compare the rows: a column that grew is
stacking, one that fell is something the rebuild no longer makes. The named-range
count is the attribute `"named_ranges"` and prints under the table.

Limits: it counts objects, not their content (a chart that moved or a rule that
now covers other cells counts the same: `dump_reference_tab()` diffs the content),
and `banded` includes the band a table carries. Seen live: a named range removed
by deleting its tab drops out of this count while its NAME stays reserved
(`addNamedRange` then answers HTTP 400, "already exists"), so delete the range
(`deleteNamedRange`) before the tab, as `gs_reset_tabs()` does. It asks for the
cell grid, so it is slower on a tab with very many rows.

## Flip-and-restore test: does the input really drive the outputs?

Reading cells proves the values are there. It does not prove that a dropdown or
input cell is wired to the outputs. Flip the input through the API, read what
depends on it, and put the input back:

```r
flip_test <- function(ss, tab, row, col, options, outputs) {
  cell <- sprintf("'%s'!%s%d", tab, col_letter(col), row)
  snap <- read_values(ss, cell, value_render = "FORMULA")[[cell]]   # snapshot BEFORE any change
  orig <- if (length(snap)) snap[1, 1] else NA                      # a formula stays a formula; NA = was empty
  put  <- function(v) { write_cell(ss, tab, row, col, v); flush_writes(ss, strict = TRUE) }
  on.exit({ put(orig); message("restored ", cell) }, add = TRUE)    # runs even if a read below fails
  stats::setNames(lapply(options, function(o) {
    put(o)
    read_values(ss, outputs, value_render = "UNFORMATTED_VALUE")[[1]]
  }), options)
}

res <- flip_test(ss, "Summary", 5, 3, c("Low", "Base", "High"), "Summary!C8:C9")
print(res)                                       # outputs per option: they must differ
back <- read_values(ss, "Summary!C5", value_render = "FORMULA")[[1]]
stopifnot(identical(back[1, 1], "Base"))         # confirm the restore with a read, not with the log line
```

Rules:

- **Snapshot first, restore in a finally-style step.** `on.exit()` inside a function (or
  `tryCatch(..., finally = )`) restores the input even when a read fails; a restore
  written after the reads is skipped by the first error. Then read the cell back and
  compare it with the snapshot.
- **A test script must never leave a sheet changed.** If the restore itself fails,
  tell the user which cell was changed and what its original value was.
- **Stay at the default access level.** Do not raise it for this test. A copy of the
  whole file (`drive_cp()`) needs the `drive` level, so it is only an option if the
  user already granted it. A scratch copy of one tab (`sheet_copy()`) works at the
  default level when the outputs sit on that same tab; formulas on the copy that point
  at other tabs still read the originals. Otherwise flip only the one input cell of the
  live tab, with the `on.exit()` restore above.
- **Text that looks like a number** (an ID such as `"00123"`) comes back as a number from
  `write_cell(orig)`. If the snapshot is such a string, restore it with `as_text = TRUE`.
- **Flip only through values the dropdown lists.** API writes bypass validation (see
  [pitfalls.md](pitfalls.md)), so an unlisted value goes in without complaint and tests nothing real.
- **Do not clear to reset.** `range_clear()` resets the formatting by default. To blank
  values use `gs_clear_values()` or `range_clear(reformat = FALSE)`.
- Check that the outputs differ between options (`stopifnot(!identical(res$Low, res$High))`);
  all options giving the same numbers is the failure this test exists to catch.

## Format audits worth adding to the checklist

Three render-defect classes the standard audits miss, all cheap via one
masked `spreadsheets.get`:

- **Gridlines**: presentation tabs usually hide them. Fetch
  `sheets.properties.gridProperties(hideGridlines)` and assert it matches the
  reference tab (the property is per-sheet, set via `updateSheetProperties`).
- **TEXT-formatted numeric cells**: a cell holding a real number but formatted
  `TEXT` ('@') renders left-aligned and won't aggregate — the classic symptom
  of a stray `'@'` pre-format on a value column. Fetch
  `effectiveFormat.numberFormat.type` + `effectiveValue` and flag cells where
  `type == "TEXT"` and `numberValue` is present. Data regions should flag zero.
- **Font/size "accent map"**: deliberate deviations from the default font
  (a monospace note row, a 9pt italic accent, per-row pixel heights) are part
  of the visual contract. Probe with a mask that includes
  `effectiveFormat.textFormat(fontFamily,fontSize,bold,italic)` **and**
  `rowMetadata.pixelSize` / `columnMetadata.pixelSize`, and list every
  non-default cell — a probe without `fontFamily` + `pixelSize` is exactly how
  such rows get silently dropped from a rebuild.

## Link cells: verify the LINK METADATA, not the formula text

A FORMULA-render regex (`^=HYPERLINK\(`) proves only that a formula string is
stored — it CANNOT prove the link works. API-written `=HYPERLINK()` formulas
render their label but never get the click-to-open chip (see pitfalls.md), so
a formula-text check happily passes on a workbook of dead links. Assert the
actual link metadata instead:

```r
# every non-empty cell in a link column must carry a real link URI
meta <- googlesheets4::request_generate("sheets.spreadsheets.get",
  params = list(spreadsheetId = ss_id, ranges = "'My Tab'!J2:J100",   # NOT URLencoded
    fields = "sheets(data(rowData(values(formattedValue,userEnteredFormat.textFormat.link))))"))
rows <- gargle::response_process(googlesheets4::request_make(meta))$sheets[[1]]$data[[1]]$rowData
for (rr in rows) {
  v <- rr$values[[1]]
  txt <- v$formattedValue %||% ""
  uri <- v$userEnteredFormat$textFormat$link$uri %||% ""
  stopifnot(!grepl("^=?HYPERLINK\\(", txt))          # no formula-as-text remnants
  if (nzchar(txt)) stopifnot(nzchar(uri))            # visible label ⇒ real link
  # optional: assert the URI's /d/<fileId> is in your known-source universe
}
```

Build links with `link_cells_req()` (gs_helpers.R), applied in a separate
batch AFTER all formatting. `fmt_cells()` keeps a link, but a hand-written
`repeatCell` with the whole-object mask (`userEnteredFormat` or
`userEnteredFormat.textFormat`) erases `textFormat.link`.
