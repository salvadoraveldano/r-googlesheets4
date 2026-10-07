# Creating Spreadsheets & Tab Management

## Creating a spreadsheet

```r
# Basic
ss <- gs4_create("Quarterly Report")

# With locale and timezone
ss <- gs4_create("Quarterly Report",
                 locale   = "en_US",
                 timeZone = "America/New_York")

# With pre-named tabs
ss <- gs4_create("Report", sheets = c("Cover", "Data", "Analytics"))

# With data pre-loaded — Sheets auto-styles each tab
ss <- gs4_create("Report", sheets = list(
  Cover     = cover_df,
  Data      = raw_data_df,
  Analytics = analytics_df
))

# Get the spreadsheet ID for subsequent ops
ss_id <- as.character(ss)        # plain string
# or                             ↓ class-aware
ss_id <- as_sheets_id(ss)
```

## Adding tabs

```r
sheet_add(ss, sheet = "New Tab")
sheet_add(ss, sheet = c("Tab1", "Tab2", "Tab3"))   # bulk
```

## Deleting tabs

```r
sheet_delete(ss, sheet = "OldTab")
```

## Renaming tabs

```r
sheet_rename(ss, sheet = "Old Name", new_name = "New Name")
```

## Reordering tabs

```r
sheet_relocate(ss, sheet = "Cover", .before = 1)   # make it first
sheet_relocate(ss, sheet = "Notes", .after = "Data")
```

## Resizing a tab

```r
sheet_resize(ss, sheet = "Data", nrow = 1000, ncol = 20, exact = TRUE)
```

## Copying a tab

```r
# Within the same spreadsheet
sheet_copy(ss, from_sheet = "Template", to_sheet = "Copy")

# To a different spreadsheet
sheet_copy(from_ss, from_sheet = "Template",
           to_ss = target_ss, to_sheet = "Imported")
```

⚠️ `sheet_copy()` carries over `hiddenByUser` columns. If the source had
columns A or B hidden, the copy does too — and your subsequent writes to
`A1` will be invisible. Always run `first_visible_col()` after copying.
See [qa-post-build.md](qa-post-build.md).

## Idempotent tab rebuilds preserve merges

A build that recreates a tab — `sheet_delete()` then `sheet_add()` — produces
a clean sheet and therefore **wipes any manual cell merges** the user added
(banners, section headers). If your build is the source of truth, re-apply
them from a declarative **merge registry** at the end of the build.

To stay idempotent and dodge "already merged"/intersecting errors (the tab's
own format step may have merged some of the same rows), pair `fmt_unmerge()`
with `fmt_merge()` in ONE atomic batch per tab — unmerge is a no-op when
nothing's there:

```r
LAYOUT_MERGES <- list(
  list(sid_report, c("A1:H1", "A2:H2")),   # banner + reading-guide
  list(sid_detail, c("B3:F3"))
)
for (e in LAYOUT_MERGES) {
  reqs <- list(); sid <- e[[1]]
  for (a1 in e[[2]]) { g <- a1_range(a1)    # your A1->grid parser
    reqs <- c(reqs, list(fmt_unmerge(sid, g$r1,g$r2,g$c1,g$c2),
                         fmt_merge  (sid, g$r1,g$r2,g$c1,g$c2))) }
  batch_format(ss, reqs)                    # per-tab → one failure can't nuke the rest
}
```

Two gotchas this pattern lives with (full detail in [pitfalls.md](pitfalls.md)):
a full-width `A:*` merge requires the tab to freeze **rows only**
(`frozenColumnCount = 0`), and re-probe the live merges
(`spreadsheets.get fields=sheets(properties(title),merges)`) whenever you need
to refresh the registry after the user adds more.

## Getting tab properties (and the sheetId you need for batchUpdate)

```r
props <- sheet_properties(ss)
# tibble: name | index | id (the sheetId) | grid_rows | grid_columns | …

# Convenience helper from gs_helpers.R
sid <- get_sheet_id(ss, "Cover")
```

The first sheet is usually `id == 0` but never assume — always look up.
After deleting and re-adding sheets, the IDs are non-contiguous integers.
