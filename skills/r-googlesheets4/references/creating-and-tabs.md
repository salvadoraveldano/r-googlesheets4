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

## Create-or-reuse for rebuild scripts: `gs_open_or_create()`

A build script should edit ONE file on every run, not leave a new one in Drive
each time. `gs_open_or_create()` (in `gs_helpers.R`) creates the file, or, when
`SHEET_ID` is set, reuses it and adds any missing tabs. It prints the id so the
next run is `SHEET_ID=<id> Rscript build.R`.

```r
ss <- gs_open_or_create("Quarterly Report", c("Cover", "Data", "Forecast"),
                        time_zone = "Etc/GMT", locale = "en_US",
                        rows = 300, cols = c(Forecast = 31))
```

| Argument | Meaning |
|---|---|
| `time_zone` | **Create only.** Default `Sys.timezone()` (so datetimes written from R round-trip; skipped when R cannot tell). `"Etc/GMT"` gives a neutral file with no author region; `NULL` leaves Google's default. |
| `locale` | **Create only.** `"en_US"` makes `0.016` parse as a number and `TEXT()` formats behave. `NULL` = Google's default. |
| `rows`, `cols` | Grid size: one number for every tab, or a vector named by tab (an unnamed vector longer than 1 stops). Applied on **every** run; making a grid smaller deletes the cells outside it. `NULL` keeps 1000 x 26. |
| `allow_mismatch` | **Reuse only.** Default `FALSE`: see the title guard below. `TRUE` reuses any file. |

A reused file keeps its own time zone and locale (changing them on every rerun
would be a surprise); update them with an `updateSpreadsheetProperties` request
if you must. When a reuse has to add a tab that was not there, the function
says so in a message: that usually means `SHEET_ID` points at the wrong file.

**Title guard.** On reuse it reads the file once (title and tab names) BEFORE it
adds a tab or changes anything, and stops unless the file's title is exactly
`title` or the file already has ALL of `tabs`. A wrong `SHEET_ID` therefore
fails with `SHEET_ID is a file titled 'X' but this script builds 'Y' and the
file does not have its tabs. Nothing was changed.` instead of receiving your
tabs and, with `gs_reset_tabs()`, being wiped. A renamed copy of your own file
still works (it has all the tabs). Pass `allow_mismatch = TRUE` only when you
mean to reuse a file that is neither. Build scripts no longer need their own
title check before calling it.

Limit: the "has all the tabs" shortcut is weak for generic tab names. A file with a
`Summary` or `Sheet1` tab passes a script that builds only that tab, so a wrong id
that happens to hold such a tab is not caught. Confirm the id with the user when the
script builds only generic names.

## Rebuilding in place: `gs_reset_tabs()`

`gs_open_or_create()` only adds missing tabs. A second run of the build would
still hit HTTP 400 on `addNamedRange`, `addBanding`, `addProtectedRange`,
`addFilterView` and `addTable` ("already exists"), and would **stack** charts,
slicers, conditional-format rules and row/column groups (each rerun adds
another). Start every rebuild from a blank slate:

```r
ss <- gs_open_or_create(TITLE, TABS)
gs_reset_tabs(ss, tabs = TABS)                        # the tabs this script builds
gs_reset_tabs(ss, c("Model", "Dash"))                 # only these tabs
gs_reset_tabs(ss, googlesheets4::sheet_names(ss))     # every tab: say so on purpose
gs_reset_tabs(ss, "Dash", keep_values = TRUE)         # keep the cell values, rebuild the rest
```

`tabs` is **required**: a character vector of the tab names to wipe. Leaving it
out (or `NULL`, `character(0)`, `NA`, a non-character value) stops before any
request is sent, with `Nothing was changed.`; there is no "every tab" default,
so a wrong `SHEET_ID` cannot clear a whole file by accident. A name that is not
in the file stops with `no such tab(s)`.

From one `spreadsheets.get` it deletes, by id, the charts, slicers, tables,
banded ranges, protected ranges, filter views, conditional-format rules, row and
column groups, and the named ranges on those tabs. Then, per tab, it clears the
basic filter, merges, data validation, notes, pivot tables, formats and values,
un-hides rows and columns, resets row heights (21px) and column widths (100px),
and unfreezes rows and columns (a leftover freeze makes the next build's banner
merge fail). The tabs, their sheetIds and the grid size stay.

- It wipes **everything** on the tabs you name. Only run it on a file the
  script owns, never on a hand-edited workbook.
- **Deleting a named range rewrites every formula that uses it to `#REF!`, for
  good.** Re-adding the name does not repair them (checked live: `=NR_X*2`
  becomes `=#REF!*2`). Reset together every tab whose formulas use the names
  being deleted (all tabs with `googlesheets4::sheet_names(ss)`), and write
  those formulas again after the reset. Add the named ranges before the formulas that use them, as always.
- `keep_values = TRUE` keeps the values and formulas, so it also **keeps the
  named ranges** (deleting them would corrupt the kept formulas). A rebuild
  must then skip `fmt_named_range()` for names that already exist, which would
  answer HTTP 400.
- Heights are pinned back to 21px, so wrapped text no longer auto-grows:
  finish with `fmt_auto_resize_rows()` for narrative rows.
- `gs_open_or_create(rows =, cols =)` resizes the grid. To shrink a tab that
  holds groups, charts or frozen rows below the cut, reset it first (or expect
  an HTTP 400).

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

To put ALL the tabs in the order of one vector, in a single call, use
`fmt_tab_order(ss, tabs)`: it returns one `updateSheetProperties` (index)
request per tab, so combine it with other requests using `c()`, not `list()`.

```r
batch_format(ss, fmt_tab_order(ss, c("Cover", "Data", "Forecast")), strict = TRUE)
batch_format(ss, c(list(fmt_freeze(sid_data, rows = 1L)),
                   fmt_tab_order(ss, c("Data", "Cover", "Forecast"))), strict = TRUE)
# you already hold the sheetIds (no lookup call): fmt_tab_order(NULL, unname(sid))
```

The listed tabs take positions 1, 2, 3, ... in the order given. A tab you leave
out follows them in its old order (checked live: `c("Pie")` on `Data, Pie, Extra`
gives `Pie, Data, Extra`). An unknown or repeated name stops before anything is
sent. Re-run it after `gs_open_or_create()` adds tabs, which appends them at the end.

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
