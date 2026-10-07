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

# 2. Flush ALL writes in ONE API call (USER_ENTERED — formulas evaluate)
flush_writes(ss)

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
of `{range, values}` pairs. Each `write_cell()` appends to it.
`flush_writes()` sends the whole list as a single
`values.batchUpdate` request, then resets the buffer.

```r
clear_writes()   # rare — abort a partial build without flushing
```

The buffer is process-scoped. If you build multiple sheets in one R
session, flush each sheet's buffer before starting the next.

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

`style` is a list of `fmt_cells` parameters; `...` overrides win.

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

flush_writes(ss)        # one call for ALL labels + formulas
batch_format(ss, all_fmt)   # one call for ALL formatting
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
flush_writes(ss)
Sys.sleep(3)   # let Google's backend catch up
batch_format(ss, all_fmt)
```

3 seconds is enough in practice. Skip on small writes (< 50 cells).
