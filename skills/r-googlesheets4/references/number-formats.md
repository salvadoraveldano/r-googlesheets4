# Number Formats

Sheets uses ICU/CLDR format patterns. Mostly compatible with Excel, with
two important differences:

1. `[Red]` color codes from Excel are **not supported** in Sheets number
   formats. Use conditional formatting (`fmt_cond_negative()`) instead, or
   use the Sheets-specific `[Color53]` pattern (palette-indexed).
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
NUMFMT_CURRENCY_M  # $#,##0,,"M";($#,##0,,"M");"-"
NUMFMT_PCT         # 0.0%
NUMFMT_PCT_WHOLE   # 0%
NUMFMT_ACCOUNTING  # _($* #,##0_);_($* (#,##0);_($* "-"_)
NUMFMT_INT         # #,##0
NUMFMT_DATE        # yyyy-mm-dd
```

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
| Currency in millions (`$1.2M`)     | `$#,##0,,"M";($#,##0,,"M");"-"`                      |
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
| `[Color53]` | Sheets palette color (orange-red); use sparingly           |

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

`[Red]` from Excel does not work. Two options:

```r
# Option 1: Sheets-specific palette index (works in number format)
list(numberFormat = list(type = "CURRENCY",
                         pattern = "$#,##0;[Color53]-$#,##0"))

# Option 2 (preferred): conditional format rule
fmt_cond_negative(sid, 2, 20, 2, 4)   # red text for any negative
```

Option 2 layers cleanly with other formatting and is portable across
sheets.
