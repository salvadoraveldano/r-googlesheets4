# Named Ranges

## Basic creation

```r
fmt_named_range(sheet_id = 0L, name = "StaffData",
                start_row = 1L, end_row = 59L,
                start_col = 1L, end_col = 4L)
```

The helper enforces Sheets' naming rule: `^[A-Za-z_][A-Za-z0-9_]*$` —
no spaces, no leading digit, no `%` or `$`.

## Driver-based models — name every assumption cell

For financial models with a driver / Assumptions tab, create a named
range for **each individual assumption cell** and reference those names
from downstream formulas instead of cell addresses.

This makes formulas read as domain language. A reader can understand
the model without jumping back to Assumptions to figure out what
`$B$4` is.

```r
# Before — opaque
=B5*Assumptions!$B$4
=MAX(0,M16*Assumptions!$B$10)

# After — self-documenting
=B5*arpu
=MAX(0,M16*tax_rate)
```

Naming rules:
- Snake_case: `gross_margin`, not `GrossMargin %`.
- Short and meaningful — they appear inside every formula.

### Pattern: drive both requests and formula handles from one tibble

```r
named_ranges <- tibble::tibble(
  name = c("starting_customers", "mom_growth", "arpu",
           "gross_margin", "sm_base", "sm_growth",
           "rd_monthly", "ga_monthly", "tax_rate"),
  row  = 2:10
)

# 1. Write Assumptions tab
sheet_write(assumptions_df, ss = ss, sheet = "Assumptions")
sid_assumptions <- get_sheet_id(ss, "Assumptions")

# 2. Create one named range per driver — BEFORE flushing any formulas that use them
nr_requests <- lapply(seq_len(nrow(named_ranges)), function(i) {
  fmt_named_range(sid_assumptions,
                  name = named_ranges$name[i],
                  start_row = named_ranges$row[i],
                  end_row   = named_ranges$row[i],
                  start_col = 2L, end_col = 2L)
})
batch_format(ss, nr_requests)

# 3. Now USER_ENTERED formulas resolve the names
write_cell(ss, "P&L",  6L, 2L, "=B5*arpu")
write_cell(ss, "P&L", 17L, 2L, "=MAX(0,B16*tax_rate)")
flush_writes(ss)
```

⚠️ **Ordering is critical.** The `addNamedRange` requests must run
**before** you flush any formulas that reference those names. If the
names don't exist when USER_ENTERED parsing happens, the cells store
`#NAME?` errors and they don't self-heal when the range is later
created.

## Listing existing named ranges

```r
meta <- gs4_get(ss)
# meta$named_ranges — tibble of name, range, sheetId
```

## Deleting a named range

```r
list(deleteNamedRange = list(namedRangeId = "1234567890"))
```

The ID comes from `meta$named_ranges`.

## Bulk creation example

```r
batch_format(ss, list(
  fmt_named_range(1L, "StaffData",   1L,   59L, 1L,  4L),
  fmt_named_range(2L, "CostData",     1L, 1500L, 1L, 13L),
  fmt_named_range(3L, "SalesData",  1L, 5000L, 1L, 16L)
))
```
