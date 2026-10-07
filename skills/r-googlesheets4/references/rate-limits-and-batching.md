# Rate Limits & Batching

## Quotas (current as of 2026)

| Limit                      | Value                          |
|----------------------------|--------------------------------|
| Per-user read              | 60 requests / minute           |
| Per-user write             | 60 requests / minute           |
| Per-project read           | 300 requests / minute          |
| Per-project write          | 300 requests / minute          |
| Cells per spreadsheet      | 10,000,000                     |
| Tabs per spreadsheet       | unlimited (practical: ~200)    |
| Cell content size          | 50,000 chars                   |

`request_make()` (used by all helpers) auto-retries 429 errors with
exponential backoff via `gargle::request_retry()`. You won't see retries
in the foreground — but the wall-clock time of a "successful" call may
be 5-15s during throttling.

## The two-call rule

Every styled tab build should use exactly **2 API calls**:

1. `flush_writes(ss)` — one `values.batchUpdate` for ALL cell writes.
2. `batch_format(ss, all_fmt)` — one `batchUpdate` for ALL formatting.

```r
# BAD — 100 separate API calls (slow, eats rate limit)
for (row in 1:100) {
  range_write(ss, single_value, range = sprintf("B%d", row))
  batch_format(ss, list(fmt_cells(0, row, row, 1, 6, bold = TRUE)))
}

# GOOD — 2 API calls regardless of cell count
for (row in 1:100) write_cell(ss, "Data", row, 2, single_value)
flush_writes(ss)
fmt <- lapply(1:100, function(r) fmt_cells(0, r, r, 1, 6, bold = TRUE))
batch_format(ss, fmt)
```

## Multi-tab and multi-sheet builds

For a build with N tabs, expect 2N + a few API calls:

| Phase                              | Calls        |
|------------------------------------|--------------|
| `gs4_create()` + initial tabs      | 1            |
| Per tab: bulk data via `sheet_write` | 1 per tab |
| Per tab: `flush_writes()`          | 1 per tab    |
| Per tab: `batch_format()`          | 1 per tab    |
| `sheet_relocate()` reorders        | 1 per move   |
| `drive_share()` calls              | 1 per share  |

So a 5-tab dept summary = roughly 17 API calls. Per the 60/min quota,
you can do ~3.5 dept summaries / minute = a 12-dept loop in ~4 minutes
without throttling.

## When to `Sys.sleep()`

- **After `flush_writes()` before the next `batch_format()`** on the same
  tab when writing > 50 cells: `Sys.sleep(3)`. Lets Google's backend fully
  commit the values before formatting reads them.
- **Between departments** in a multi-dept loop: `Sys.sleep(3)`. Reduces
  retries; still well within quota.
- **After a transient 429**: `Sys.sleep(30)`. `gargle` already retries,
  but a brief manual pause helps if the throttle persists.

```r
for (dept in DEPARTMENTS) {
  build_dept_sheet(dept)
  Sys.sleep(3)   # smooth out the loop
}
```

## What NOT to retry on

- HTTP 400 — your request is malformed; retrying won't help. Inspect the
  error body via `httr::content(resp, "text")`.
- HTTP 403 — permission denied; check the auth scope.
- HTTP 404 — sheet or tab doesn't exist; check the IDs.

HTTP 500/503 are usually transient on Sheets — retry once after
`Sys.sleep(5)`; if the identical request keeps failing, treat it like a
400 (some malformed requests surface as 500, e.g. the
`addTable`+DROPDOWN case in [pitfalls.md](pitfalls.md)).

## Avoiding cell-limit surprises

A single `gs4_create()` with `sheets = list(big_df = df)` allocates
the full grid. If `df` is 50 cols × 200K rows = 10M cells, you've hit
the cap on creation. Either split data across spreadsheets or use
`sheet_resize()` to shrink the empty default tab and write only what
you need.
