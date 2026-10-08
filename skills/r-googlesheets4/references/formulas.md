# Formulas

Sheets formulas mostly match Excel; key differences:

- Argument separator is **always comma** (no locale variation).
- Full-column refs (`A:A`) work — no need for explicit `$A$2:$A$59`.
- `QUERY()`, `IMPORTRANGE()`, `SPARKLINE()`, `GOOGLEFINANCE()`,
  `GOOGLETRANSLATE()`, `IMAGE()` are Sheets-only.
- Cross-sheet refs need single quotes when names have spaces:
  `'P&L Summary'!A1:A10`.

## Writing formulas

Mark formula strings via `gs4_formula()`:

```r
df <- tibble(
  metric = c("Total", "Average"),
  value  = gs4_formula(c("=SUM(B2:B100)", "=AVERAGE(B2:B100)"))
)
range_write(ss, df, sheet = "Summary", range = "A1", reformat = FALSE)
```

Or via the buffer (preferred for many cells):

```r
write_cell(ss, "Summary", 5, 6, '=SUMIFS(Revenue!P:P,Revenue!B:B,$C$1)')
flush_writes(ss, strict = TRUE)   # USER_ENTERED — formulas evaluate
```

## Generic SUMIFS builder

`scripts/gs_formulas.R` ships `f_sumifs()` for parameterized construction:

```r
source("scripts/gs_formulas.R")

# Single criterion
f_sumifs("People!C:C", list("People!A:A" = "Technology"))
# → '=SUMIFS(People!C:C,People!A:A,"Technology")'

# Multiple criteria
f_sumifs("OPEX!M:M",
         list("OPEX!C:C" = "Sales",
              "OPEX!I:I" = "SaaS"))
# → '=SUMIFS(OPEX!M:M,OPEX!C:C,"Sales",OPEX!I:I,"SaaS")'

# Cell-reference criterion (auto-detected — no quotes added)
f_sumifs("Revenue!P:P",
         list("Revenue!B:B" = "$C$1"))
# → '=SUMIFS(Revenue!P:P,Revenue!B:B,$C$1)'
```

For project-specific shortcuts, write thin wrappers locally:

```r
f_people_by_alloc <- function(dept) {
  f_sumifs("People!C:C", list("People!B:B" = dept))
}
f_people_by_alloc("Technology")
# → '=SUMIFS(People!C:C,People!B:B,"Technology")'
```

## SUMIFS criteria semantics (live-verified idioms)

Behaviors of `SUMIFS`/`COUNTIF` criteria in Google Sheets that differ from
intuition (and from Excel) — each one verified against a live sheet:

- **Array criteria don't iterate.** `SUM(SUMIFS(amounts, col, FILTER(olds, sel)))`
  silently uses only the **first** element of the array — no error, wrong total.
  For "sum where col is IN a list", use SUMPRODUCT membership instead:
  `=SUMPRODUCT((COUNTIF(FILTER(olds, news=sel), col) > 0) * amounts)` —
  `COUNTIF(list, col) > 0` vectorizes inside `SUMPRODUCT`.
- **Criteria are case-insensitive but whitespace-sensitive.** `"sales"` matches
  `"Sales"`, but a trailing space in either side kills the match — trim/normalize
  taxonomy strings at the source.
- **Wildcards are live in criteria.** `*`, `?`, and `~` are active; a literal
  `*` or `?` in a value must be escaped with `~` (e.g. matching the literal
  vendor `"Acme*"` needs criteria `"Acme~*"`).
- **Blank matching:** `SUMIFS(amounts, col, "")` matches truly-blank cells.
  But `"="&ref` where `ref` is empty matches **nothing** in Sheets (unlike
  Excel, where it matches blanks) — don't port that Excel idiom.
- **Bound your ranges.** Whole-column `SUMPRODUCT` over `A:A` evaluates the
  full million-row grid; use bounded ranges (`A2:A5000`) in generated formulas.

## Safe division

```r
f_safe_div("B10", "B5")
# → '=IF(B5=0,"",B10/B5)'
```

Avoids `#DIV/0!` and the awkward visual of an error in a margin cell.

## The double-equals bug

Each formula builder returns `=SUMIFS(...)`. Combining two builders into
one cell formula via naive `glue("={f_a()}+{f_b()}")` produces
`==SUMIFS(...)+==SUMIFS(...)` — a syntax error.

```r
# BUG
write_cell(ss, sn, r, 3,
  glue("={f_a(dept)}+{f_b(dept)}"))     # → ==SUMIFS(...)+==SUMIFS(...)

# FIX: fraw() strips the leading "="
write_cell(ss, sn, r, 3,
  glue("={fraw(f_a(dept))}+{fraw(f_b(dept))}"))
# → =SUMIFS(...)+SUMIFS(...)
```

| Scenario                          | Pattern                                                        |
|-----------------------------------|----------------------------------------------------------------|
| Single builder → cell             | `write_cell(ss, sn, r, 3, f_rev(dept, REV_GROSS))`             |
| Two+ builders combined            | `glue("={fraw(f_a(...))}+{fraw(f_b(...))}")`                   |
| Builder + cell reference          | `glue("={fraw(f_a(...))}-C{other_row}")`                       |
| Pure cell references              | `glue("=C{row1}-C{row2}")`                                     |

## QUERY — Sheets-only SQL

```r
f_query <- function(data_range, query, header = 0L) { … }

# Top 10 vendors by amount
f_query("OPEX!A:M",
        "SELECT I, F, SUM(M) WHERE C = 'Sales' GROUP BY I, F ORDER BY SUM(M) DESC LIMIT 10",
        header = 0L)
```

Patterns:
- `LIMIT 10` for top-N.
- `UPPER(G)` for case-insensitive grouping.
- `WHERE col = '"&$C$1&"'` to inject a dynamic department from a header cell.
- Last arg `0` = no header row in QUERY output.
- QUERY auto-expands into adjacent cells (spillover) — keep the area clear.

## Other Sheets-only functions

```r
gs4_formula('=SPARKLINE(B2:M2, {"charttype","bar";"color1","#2457C5"})')
gs4_formula('=GOOGLEFINANCE("GOOG", "price")')
gs4_formula('=GOOGLETRANSLATE(A2, "en", "es")')
gs4_formula('=IMPORTRANGE("spreadsheet_url", "Sheet1!A1:Z100")')
gs4_formula('=IMAGE("https://example.com/logo.png")')
```

`IMPORTRANGE` requires explicit per-spreadsheet authorization the first
time the formula evaluates (a popup in the UI). For automation, prefer
`drive_cp` + a single-sheet model.

### SPARKLINE options: numbers are numbers

In a SPARKLINE options array, a number must be written bare and a string must
be quoted. A quoted number is an error (checked live):
`{"linewidth","3"}` gives `#VALUE!` ("option linewidth expects number values.
But '3' is a text"), `{"linewidth",3}` draws the line. `f_sparkline()` keeps
the R type of each option and quotes only the strings:

```r
f_sparkline("B2:M2", list(charttype = "line", linewidth = 2, color = "#2457C5"))
# → '=SPARKLINE(B2:M2, {"charttype","line";"linewidth",2;"color","#2457C5"})'

# Wrap a value in I() to write it as-is: a cell reference or an expression
f_sparkline("H2", list(charttype = "bar", max = I("$H$1"),
                       color1 = I('IF(H2>1,"#E5484D","#18A957")')))
# → '=SPARKLINE(H2, {"charttype","bar";"max",$H$1;"color1",IF(H2>1,"#E5484D","#18A957")})'
```

`charttype` is one of `line`, `column`, `winloss`, `bar` (any other value is a
`#VALUE!` that names the allowed ones). `TRUE` / `FALSE` options such as `rtl`
are written bare too.

A SPARKLINE over a row with no numbers shows `#N/A` (checked live). Pass
`iferror = TRUE` to wrap it in `IFERROR(..., "")`, so an empty row stays an empty
cell and a row with data still draws:

```r
f_sparkline("E3:K3", list(color = "#2457C5"), iferror = TRUE)
# → '=IFERROR(SPARKLINE(E3:K3, {"color","#2457C5"}),"")'
```

`hex_to_color()` and the `COL_*` constants are API colours (0-1 floats), not hex
text. `color_to_hex()` converts one back for an option like `color`:

```r
f_sparkline("B2:M2", list(color = color_to_hex(COL_RED_TEXT)))
# → '=SPARKLINE(B2:M2, {"color","#C62828"})'
```

`color_to_hex(hex_to_color("#2457C5"))` returns `"#2457C5"`. A channel the API
leaves out counts as 0, so a colour read back from a sheet works too.

## LET, LAMBDA, MAP: array expressions are scalar inside a binding

`LET`, `LAMBDA`, `MAP` and `BYROW` go through the API like any formula, but
arithmetic or a comparison on a whole range (`E1:E5*2`, `(f>2)*(f<5)`) is only
computed cell by cell inside `ARRAYFORMULA()` or an array-aware function such as
`SUMPRODUCT` or `MAP`. A `LET` binding and a `LAMBDA` body do NOT supply that
array context, so the expression is evaluated as a scalar there (the same is
true of a bare `=SUM(E1:E5*2)`). The failure has two faces, and the quiet one
is the dangerous one:

- On a row that has no cell of the range, the cell shows `#VALUE!` ("The default
  output of this reference is a single cell in the same row but a matching value
  could not be found. To get the values for the entire range use the
  ARRAYFORMULA function").
- On a row that DOES intersect the range, Sheets silently picks that row's
  value (implicit intersection) and returns a plausible, wrong number. A
  burn-down sum built this way was wrong with no error anywhere.

Checked live with `E1:E5` = 1..5:

| Formula | Result |
|---|---|
| `=LET(x, E1:E5*2, SUM(x))` | typed in row 3: **6**, no error (correct: 30); on a row outside the range `#VALUE!` |
| `=LET(f, E1:E5, g, (f>2)*(f<5), SUM(g))` | typed in row 4: **1**, no error (correct: 2); elsewhere `#VALUE!` |
| `=LET(x, ARRAYFORMULA(E1:E5*2), SUM(x))` | 30 |
| `=LET(f, E1:E5, g, ARRAYFORMULA((f>2)*(f<5)), SUM(g))` | 2 |
| `=LET(x, E1:E5, SUMPRODUCT((x>2)*1))` | 3 (`SUMPRODUCT` forces array context) |
| `=LET(x, E1:E5, SUM(--(x>2)))` | `#VALUE!` |
| `=LET(x, E1:E5, SUM(ARRAYFORMULA(--(x>2))))` | 3 |
| `=LET(f, LAMBDA(a, a*2), SUM(f(E1:E5)))` | `#VALUE!` |
| `=LET(f, LAMBDA(a, ARRAYFORMULA(a*2)), SUM(f(E1:E5)))` | 30 |
| `=SUM(MAP(E1:E5, LAMBDA(v, v*2)))` | 30 |
| `=SUM(BYROW(E1:E5, LAMBDA(r, r*2)))` | 30 |
| `=MAP(E1:E5, LAMBDA(v, v + SUM(E1:E5*2)))` | `#VALUE!` in every row: the inner `E1:E5*2` is scalar too |
| `=SUM(E1:E5*2)` (no `LET` at all) | same trap; `=ARRAYFORMULA(SUM(E1:E5*2))` and `=SUMPRODUCT(E1:E5*2)` give 30 |

The rules that follow:

- Wrap every array-valued `LET` binding and every array expression inside a
  `LAMBDA` body in `ARRAYFORMULA()`, or compute it with an array-aware function
  (`SUMPRODUCT`, `MAP` and `BYROW` were checked).
- `MAP(range, LAMBDA(v, ...))` and `BYROW` are fine for the element-wise part;
  the trap is only what you do with a whole range *inside* the lambda.
- Do not trust "no error" on a formula that works with ranges inside `LET`:
  read the value back (`UNFORMATTED_VALUE`) and compare it with a number you
  computed independently in R.

A related zero-denominator trick: `(x-y)+(x<=y)` reads like "x-y, or 1 when
x<=y", but it is 0 when `x-y = -1` (x=4, y=5 gave `#DIV/0!`). Use
`(x-y)*(x>y)+(x<=y)`: it is `x-y` when `x>y` and 1 otherwise (10 divided by it
gave 10 live).

Both traps are also in [pitfalls.md](pitfalls.md) (`LET()` bindings evaluate in
scalar context; `(x-y)+(x<=y)` is not a safe zero-denominator guard).

## Hyperlinks — use rich-text links, not `=HYPERLINK()`

> ⚠ **API-written `=HYPERLINK()` formulas don't work on first click.** The
> formula evaluates (the label renders) but Sheets never generates the
> click-to-open `hyperlink` chip metadata for formulas written via the values
> API — the user must re-enter each cell (enter → space → enter) to activate
> it. This is invisible to a FORMULA-render regex check and once shipped a
> whole workbook of dead links. Full row in [pitfalls.md](pitfalls.md).

- **Rich-text link (the default for any clickable link)** — write the label
  string with `userEnteredFormat.textFormat.link.uri` via `updateCells`:
  `link_cells_req(sheet_id, row1, col1, labels, urls)` in `gs_helpers.R`
  builds one request per column of links; `parse_hyperlink()` migrates
  existing `=HYPERLINK(...)` content strings. Always clickable, renders as
  the standard blue underlined link. Apply link requests in a separate batch
  AFTER all formatting. `fmt_cells()` keeps a link (its masks are per
  property), but a hand-written `repeatCell` with the whole-object mask
  (`userEnteredFormat` or `userEnteredFormat.textFormat`) wipes
  `textFormat.link`; putting links last stays the safe order. QA by asserting
  `textFormat.link.uri` presence.
- **`=HYPERLINK("#gid=<sheetId>&range=B5","Go to P&L")`** — only for
  intra-sheet navigation entered/re-entered by humans. The URL is a
  **literal string**: it does NOT shift when rows move — after structural
  row changes, re-write the links with corrected `range=` (see the pitfall
  in [pitfalls.md](pitfalls.md)). If written via the API it has the dead-link
  problem above.
- **`textFormatRuns[].format.link.uri`** — variant of the rich-text link for
  linking only PART of a cell's text.

## Build-time vs sheet-time conditionals

Build-time: a hardcoded `if (m_idx <= 3) actual_branch else forecast_branch`
in your R script bakes the boundary into the formulas. Re-running the
script changes the boundary.

Sheet-time: wrap formulas in an IF that branches on a single named cell.
The user changes ONE cell to flip the boundary, no rebuild needed.

```r
NAMED_LAST_ACTUAL <- "Config!$B$2"   # named cell for last actual month index

write_cell(ss, "P&L", row, c2,
  sprintf("=%s * IF(%d > %s, %s, 1)",
          val_eff, i, NAMED_LAST_ACTUAL, scaling))
```

See [finance-models.md](finance-models.md) for the full pattern.
