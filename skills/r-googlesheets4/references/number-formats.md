# Number Formats

Sheets uses ICU/CLDR format patterns. Mostly compatible with Excel, with
two important differences:

1. A format can colour a section only with a named colour (`[Red]`,
   `[Blue]`, `[Green]` … or `[ColorN]`, checked live 2026-10), never an exact
   hex. For the design system's red, use conditional formatting
   (`fmt_cond_negative()`) instead.
2. Comma is always the argument separator in formulas, regardless of
   locale. (Excel uses `;` in EU locales — Sheets doesn't.)

## API shape

```r
list(numberFormat = list(type = "NUMBER", pattern = '$#,##0;($#,##0);"-"'))
```

`type` ∈ `TEXT` / `NUMBER` / `PERCENT` / `CURRENCY` / `DATE` / `TIME` /
`DATE_TIME` / `SCIENTIFIC`.

## Constants in `gs_helpers.R`

```r
NUMFMT_CURRENCY    # $#,##0;($#,##0);"-"
NUMFMT_CURRENCY_K  # $#,##0,"K";($#,##0,"K");"-"
NUMFMT_CURRENCY_M  # $#,##0,,"M";($#,##0,,"M");"-"           rounds $3.5M to "$4M"
NUMFMT_CURRENCY_M1 # $#,##0.0,,"M";($#,##0.0,,"M");"-"       $3.5M: millions for a board
NUMFMT_PCT         # 0.0%
NUMFMT_PCT_WHOLE   # 0%
NUMFMT_ACCOUNTING  # _($* #,##0_);_($* (#,##0);_($* "-"_)
NUMFMT_INT         # #,##0
NUMFMT_DATE        # yyyy-mm-dd

# Deltas (KPI changes, variances): a sign on every change, a dash for zero
NUMFMT_DELTA_PCT      # +0.0%;-0.0%;"-"            type PERCENT
NUMFMT_DELTA_PT       # +0.0" pts";-0.0" pts";"-"  store points: =(a-b)*100
NUMFMT_DELTA_CURRENCY # +$#,##0;-$#,##0;"-"
```

`fmt_kpi_strip()` uses `NUMFMT_DELTA_PCT` for its delta row by default. A zero
change prints "-" and gets no colour.

Apply via `fmt_cells()`:

```r
fmt_cells(sid, 2, 20, 2, 4,
          numfmt_type    = NUMFMT_CURRENCY$type,
          numfmt_pattern = NUMFMT_CURRENCY$pattern)
```

## Common patterns

| Goal                               | Pattern                                              |
|------------------------------------|------------------------------------------------------|
| Currency (USD)                     | `$#,##0;($#,##0);"-"`                                |
| Currency in thousands (`$1.2K`)    | `$#,##0,"K";($#,##0,"K");"-"`                        |
| Currency in millions (`$1M`)       | `$#,##0,,"M";($#,##0,,"M");"-"`                      |
| Currency in millions (`$1.2M`)     | `$#,##0.0,,"M";($#,##0.0,,"M");"-"`                  |
| Signed change (`+4.2%`)            | `+0.0%;-0.0%;"-"`                                    |
| Accounting (right-aligned `$`)     | `_($* #,##0_);_($* (#,##0);_($* "-"_)`               |
| Percentage (one decimal)           | `0.0%`                                               |
| Percentage (whole)                 | `0%`                                                 |
| Whole-number with thousands sep    | `#,##0`                                              |
| Date ISO                           | `yyyy-mm-dd`                                         |
| Date long                          | `mmmm d, yyyy`                                       |
| Time                               | `h:mm AM/PM`                                         |

## Custom patterns

Pattern grammar:

| Token       | Meaning                                                    |
|-------------|------------------------------------------------------------|
| `0`         | Required digit                                             |
| `#`         | Optional digit (no leading zero)                           |
| `,`         | Thousands separator (or scaling — see below)               |
| `.`         | Decimal point                                              |
| `;`         | Section separator: positive ; negative ; zero ; text       |
| `_x`        | Skip width of char x (alignment trick)                     |
| `*x`        | Repeat char x to fill remaining width                      |
| `"text"`    | Literal text                                               |
| `[Red]`     | Named colour for that section (`[Black]`, `[Blue]`, `[Green]`, `[Red]`, … or `[ColorN]`); never a hex |

### Scaling via comma

`,` after the last digit divides by 1,000:

| Pattern              | 1234567 →  | What                             |
|----------------------|------------|----------------------------------|
| `#,##0`              | `1,234,567`| Standard                         |
| `#,##0,`             | `1,235`    | Show in thousands, no suffix     |
| `#,##0,"K"`          | `1,235K`   | Show as Ks                       |
| `#,##0,,"M"`         | `1M`       | Show as millions                 |
| `#,##0.0,,"M"`       | `1.2M`     | Millions with one decimal        |

### Negatives in red — use conditional formatting

Two options:

```r
# Option 1: a named colour in the format itself (`[Red]` and `[ColorN]` both work)
list(numberFormat = list(type = "CURRENCY",
                         pattern = "$#,##0;[Red]-$#,##0"))

# Option 2 (preferred): conditional format rule
fmt_cond_negative(sid, 2, 20, 2, 4)   # red text for any negative
```

Option 2 layers cleanly with other formatting, takes the exact
`COL_NEGATIVE` hex, and keeps red off model grids (apply it to output tabs
only; [design-principles.md](design-principles.md)).
