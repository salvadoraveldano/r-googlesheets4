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
flush_writes(ss)   # USER_ENTERED — formulas evaluate
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
  AFTER all formatting — `fmt_cells()` with any textFormat arg wipes
  `textFormat.link`. QA by asserting `textFormat.link.uri` presence.
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
