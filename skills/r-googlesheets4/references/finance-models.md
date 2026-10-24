# Finance-Model Patterns

Patterns surfaced from building cashflow scenario engines.
Use these when stitching a multi-tab model where:

- The user needs ad-hoc override capability over computed source values.
- A single named cell controls the actual / forecast boundary.
- Summary sections fan out a single closing-cash anchor across multiple
  sensitivity levels.
- The source workbook holds expense rows in pre-signed (negative) form.
- Inputs, formulas and links need to be told apart at a glance (§9).
- The model needs visible integrity checks and a pass/fail badge (§10).

## 1. Source / Override / Effective row pattern

For each metric a downstream tab depends on, structure 3 rows:

```
Source     (formula, locked, gray)        ← computed via SUMIFS, IF, etc.
Override   (yellow input, blank default)  ← user types a number to override
Effective  (formula, used downstream)     ← =IF(ISNUMBER(<override>), <override>, <source>)
```

Downstream tabs reference the **Effective** row only. The user changes
ONE cell to override; everything downstream updates.

```r
sd_make_soe_block <- function(hdr_row, src_row, ovr_row, eff_row,
                              hdr_label, source_fn, ovr_default = "") {
  write_cell(ss, SD_TAB, hdr_row, COL_LABEL, hdr_label)
  write_cell(ss, SD_TAB, src_row, COL_LABEL, "  Source (raw data — read-only)")
  write_cell(ss, SD_TAB, ovr_row, COL_LABEL, "  Override (yellow — blank by default)")
  write_cell(ss, SD_TAB, eff_row, COL_LABEL, "  Effective (used downstream)")
  for (i in seq_along(MONTH_COLS_24)) {
    c2 <- MONTH_COLS_24[i]; cl <- col_letter(c2)
    write_cell(ss, SD_TAB, src_row, c2, source_fn(i))
    write_cell(ss, SD_TAB, ovr_row, c2, ovr_default)
    write_cell(ss, SD_TAB, eff_row, c2,
               sprintf("=IF(ISNUMBER(%s%d),%s%d,%s%d)",
                       cl, ovr_row, cl, ovr_row, cl, src_row))
  }
}
```

**When to use:** source formula is complex/data-driven, users need
ad-hoc overrides but rarely use them.
**When NOT to use:** the input is already a yellow input row (e.g.,
a fixed repayment schedule) — just use the single row.

## 2. Sheet-time gating via single named cell

Build-time conditionals like `if (m_idx <= 3) actual_branch else forecast`
hardcode the boundary into the script. To make it **configurable in
the sheet without rebuilding**, wrap every formula in a sheet-level IF:

```r
NAMED_LAST_ACTUAL <- "Config!$B$2"   # named cell

# Revenue (forecast scales, actual doesn't):
rev_factor <- sprintf("IF(%d>%s,%s,1)", i, NAMED_LAST_ACTUAL, scaling)
write_cell(ss, TAB, top + B$rev, c2,
           sprintf("=%s * %s + %s", val_eff, rev_factor, db_eff))

# OPEX (forecast applies reduction, actual doesn't):
opex_factor <- sprintf("IF(%d>%s,(1 - %s),1)",
                       i, NAMED_LAST_ACTUAL, NAMED_OPEX_REDUCTION)
write_cell(ss, TAB, top + B$opex, c2,
           sprintf("=%s * %s", opex_eff, opex_factor))

# Actual/Forecast label:
write_cell(ss, TAB, top + B$status_strip, c2,
           sprintf('=IF(%d>%s,"Forecast","Actual")', i, NAMED_LAST_ACTUAL))
```

User edits one cell (e.g., 3 → 4); Apr flips from Forecast to Actual
everywhere — revenue stops being scaled, the status strip flips, and
forecast-only allocations stop.

**Cost:** ~2× formula complexity per cell.
**Benefit:** idempotent — no R-script rerun on month-end.
Use for the "what's actual now" boundary; don't use for genuinely
constant boundaries (FY27 starts at month 13 forever).

## 3. Reconciliation block: components → total → Δ vs canonical

When you stitch a total from multiple components (e.g., FY26 Revenue =
Q1 actuals + Apr-Dec budget + a new business line), build an
**explicit reconciliation block** instead of trusting components to
add up silently:

```
(a) Q1 2026 actuals          $1,000,000   ← =SUM('Actuals'!U14:W14)
(b) Apr-Dec budget            $3,000,000   ← computed
(c) New business line FY26   $0           ← computed
(=) Total                    $4,000,000   ← =a+b+c
Δ vs Total Revenue Effective $0           ← =total − canonical; should be 0
```

If Δ ≠ 0 at runtime, the formulas don't tie — visible to anyone who
opens the tab. The pattern doubles as: (a) regression test (Δ should
always be 0); (b) self-documenting prompt to populate inputs (when Q1
per-category cells are zero, Δ surfaces "user needs to populate" without
you flagging it).

## 4. Anchor cells + audit row

For summary sections that fan out a single value (e.g., per-scenario
Dec'26 closing cash) across many cells, **document the anchor cells in
a dedicated audit row** so addresses are visible and self-update across
row-plan shifts:

```r
close_dec26 <- function(top) sprintf("%s%d", col_letter(COL_FY26_END), top + B$close_bal)

# Audit row:
write_cell(ss, TAB, R$audit_first + 1L, COL_LABEL,
           sprintf('="FY26 close anchors per scenario: %s, %s, %s, %s, %s, %s"',
                   close_dec26(scenarios[[1]]$top), close_dec26(scenarios[[2]]$top),
                   close_dec26(scenarios[[3]]$top), close_dec26(scenarios[[4]]$top),
                   close_dec26(scenarios[[5]]$top), close_dec26(scenarios[[6]]$top)))
```

When `block_height` shifts, the audit row visibly shows the new
addresses — regression is observable, not silent.

## 5. Pre-build sign sanity check (catches double-negation)

Before writing any aggregation formula that includes a leading `-`
against a source cell, **read 2-3 cells of the source and confirm the
sign**. Five seconds, prevents an iter-day rebuild.

```r
v <- read_sheet(ss, sheet = "Actuals", range = "U19:W19",
                col_names = FALSE, col_types = "n", .name_repair = "minimal")
cat("Actuals row 19 Q1 (Cost of Sales): ", round(as.numeric(unlist(v)), 0), "\n")
# Output: -100000 -90000 -95000  ← already NEGATIVE
# DO NOT add a leading - in the aggregation formula.
```

The class of bug it prevents:

- Cost of Sales rows — pre-signed negative.
- Total OPEX row — typically positive (sum of expenses).
- Bonus accrual rows — typically positive.
- Net Op Cash Flow — depends on the formula upstream; check.

If the sign convention isn't consistent across rows in the same source
tab, write the convention down at the top of the build script.

## 6. Linear-approximation sensitivity matrix

For sensitivity views where the underlying engine is non-linear in
OPEX (an allocation rule hits a cap), use a linear approximation in
the summary:

```
close_at(scenario, opex_level)
  = base_close[scenario]
  + (opex_level - opex_driver_set) * opex_apr_dec_budget * (-1)
```

Exact when `opex_level == opex_driver_set` (the §10 monthly engine);
approximation breaks down at extremes when the cap is exhausted.
**Always document in the section explainer** ("linear approximation;
§10 reflects the driver-set level exactly"). Reuse the slope expression
across §6 sub-rows, §10 per-block matrix, §8 heatmap — DRY via a single
module-level `opex_apr_dec_budget_expr`.

## 7. Visual hierarchy for time periods

Decision-month + total + muted-future col styling:

```r
# Dec'26 col — visual focus: warm bg + bold + thicker borders
list(apply_style(sid, block_top + 1L, block_bottom_row, COL_FY26_END, COL_FY26_END,
                 STYLE_BODY, halign = "RIGHT", bold = TRUE,
                 bg_color = hex_to_color("FFF8E1"),
                 numfmt_type = "CURRENCY",
                 numfmt_pattern = "$#,##0;[Color53]-$#,##0"))

# FY26 Total col — primary total style
list(apply_style(sid, block_top + 1L, block_bottom_row, COL_FY26_TOTAL, COL_FY26_TOTAL,
                 STYLE_TOTAL, bold = TRUE, ...))

# FY27 cols — muted (gray bg, smaller font)
list(apply_style(sid, block_top + 1L, block_bottom_row, COL_FY27_START, COL_M_LAST,
                 STYLE_BODY, halign = "RIGHT",
                 bg_color = hex_to_color("F5F5F5"),
                 font_color = COL_MUTED_TEXT, font_size = 9, ...))
```

Communicates priority without requiring the reader to count cols.
Apply at every row across all scenario blocks via a single loop.

## 8. Two-tab models with cross-tab refs

When tab A's formulas reference `'Tab B'!<cell>`, tab B must exist
before tab A's cells eval — otherwise `#REF!`.

Two safe patterns:
- **(a)** Create both tabs early, populate the referenced tab first,
  then populate the referring tab.
- **(b)** Populate referring tab first → cells show `#REF!`
  transitionally → populate referenced tab → refs resolve.

Pattern (a) is cleaner because QA error scans never see ephemeral
`#REF!`s. **Order in scripts:** create both tabs → constants/helpers →
flush referenced-tab content + format → flush referring-tab content
(refs resolve) → other sections → KPI/audit → QA.

## 9. Cell colour code and model conventions

Readers of a finance model expect to see at a glance which cells they
may change. Use the font colours bankers and FP&A teams already know
(constants in `brand.R`; the §9 and §10 snippets need it, sourced after
`gs_helpers.R` and `gs_buffer.R`):

| Text colour | Meaning | Constant |
|---|---|---|
| Blue | Typed input | `COL_INPUT_FG` |
| Black | Formula using cells on the same tab | `COL_FORMULA_FG` |
| Green | Formula that pulls from another tab | `COL_LINK_FG` |

Yellow fill is optional, for the handful of key assumptions a reader is
meant to change. Don't fill every input.

- **Deciding "green" at build time:** the formula text contains `!`, or
  it uses a named range that lives on another tab (`scenario`,
  `check_tol` and other names have no `!`, so a grep for `!` misses
  them).
- **Model tabs only.** The code is font colour only and applies to
  Assumptions and the calculation tabs. Summary and Checks are output
  tabs and keep their own styling, so link-green never sits next to a
  green PASS fill.
- **No number typed into a formula row.** A number lives on Assumptions
  in blue, or in a §1 Override row beside the row it overrides. §1
  mapped to the code: Source = formula colour, Override = blue text on
  yellow, Effective = formula colour.
- **One sign convention per model.** Either costs are positive and
  subtracted, or negative and summed. Write it in a note at the top of
  Assumptions; §5 shows what mixing them does.
- **Scenario switch:** one dropdown cell (`fmt_dropdown`) named
  `scenario`, and every scenario-dependent value picks with
  `=CHOOSE(MATCH(scenario,Assumptions!$D$4:$F$4,0),D10,E10,F10)`, where
  row 4 holds the scenario names (`examples/showcases/saas-model.R`).

```r
batch_format(ss, list(
  fmt_cells(asm, 6, 20, 4, 6, font_color = COL_INPUT_FG),          # Assumptions inputs
  fmt_cells(asm, 6, 8, 4, 6, bg_color = COL_YELLOW_LIGHT),         # the few key ones
  fmt_cells(pnl, 6, 11, 3, 14, font_color = COL_LINK_FG),          # rows pulling from Assumptions
  fmt_cells(pnl, 12, 12, 3, 14, font_color = COL_FORMULA_FG)),     # subtotal of rows on this tab
  strict = TRUE)
```

The templates predate this section (`templates/scenario-engine.R` marks
overrides with yellow fill only). Where they differ, follow §9.

## 10. Checks tab

A Checks tab ties independent calculation paths to each other and turns
the result into one badge that the Summary shows. It is the model's
regression test, and anyone who opens the sheet can read it. The full
version is in `examples/showcases/saas-model.R` (search for `## ---- Checks`).

Layout: an overall status cell, a tolerance cell, then one row per
check with `#`, Check, Model value, Expected, Difference, Status.
Business warnings sit in a separate block below.

```r
CK <- "Checks"; ck <- get_sheet_id(ss, CK)
CHECKS <- list(   # label, model value, expected
  list("Balance sheet balances, month 12", "='Balance Sheet'!N40", "='Balance Sheet'!N60+'Balance Sheet'!N75"),
  list("Revenue: sum of 12 months = annual total", "=SUM(PnL!C5:N5)", "=PnL!O5"),
  list("No error values on model tabs", "=SUMPRODUCT(--ISERROR(PnL!A1:O80))+SUMPRODUCT(--ISERROR(Assumptions!A1:H40))", "=0"))
WARNS <- list(    # depend on the inputs, so they never feed the badge
  list("Cash stays positive (lowest month-end)", "=MIN(PnL!C30:N30)", "=0"))
FIRST <- 7L; LAST <- FIRST + length(CHECKS) - 1L
W_FIRST <- LAST + 2L; W_LAST <- W_FIRST + length(WARNS) - 1L

batch_format(ss, list(
  fmt_named_range(ck, "model_status", 4, 4, 4, 4),
  fmt_named_range(ck, "check_tol",    4, 4, 7, 7),
  fmt_cond_text_equals(ck, FIRST, W_LAST, 7, 7, "PASS", bg_color = COL_GREEN_LIGHT, bold = TRUE),
  fmt_cond_text_equals(ck, FIRST, W_LAST, 7, 7, "FAIL", bg_color = COL_RED_LIGHT, bold = TRUE),
  fmt_cond_text_equals(ck, FIRST, W_LAST, 7, 7, "WARN", bg_color = COL_WARNING_SOFT, bold = TRUE)),
  strict = TRUE)

write_cell(ss, CK, 4, 3, "Overall status")
write_cell(ss, CK, 4, 4, sprintf('=IF(COUNTIF(G%d:G%d,"FAIL")=0,"Model ties: OK","Model ties: CHECK")', FIRST, LAST))
write_cell(ss, CK, 4, 6, "Tolerance"); write_cell(ss, CK, 4, 7, 0.01)
for (j in 1:6) write_cell(ss, CK, 6, 1L + j, c("#", "Check", "Model value", "Expected", "Difference", "Status")[j])
ck_row <- function(rw, i, x, warn = FALSE) {
  write_cell(ss, CK, rw, 2, i); write_cell(ss, CK, rw, 3, x[[1]])
  write_cell(ss, CK, rw, 4, x[[2]]); write_cell(ss, CK, rw, 5, x[[3]])
  write_cell(ss, CK, rw, 6, if (warn) sprintf("=MIN(0,ROUND(D%d-E%d,4))", rw, rw)   # only a shortfall counts
                            else sprintf('=IF((D%1$d="")<>(E%1$d=""),1,ROUND(D%1$d-E%1$d,4))', rw))   # blank vs number is a difference
  bad <- if (warn) "WARN" else "FAIL"
  write_cell(ss, CK, rw, 7, sprintf('=IFERROR(IF(ABS(F%d)<=check_tol,"PASS","%s"),"%s")', rw, bad, bad))
}
for (i in seq_along(CHECKS)) ck_row(FIRST + i - 1L, i, CHECKS[[i]])
for (i in seq_along(WARNS))  ck_row(W_FIRST + i - 1L, i, WARNS[[i]], warn = TRUE)
flush_writes(ss, strict = TRUE)
# Summary: write_cell(ss, "Summary", 5, 11, "=model_status")
```

What to check:

- Totals that tie across tabs, and any stitched total against its
  canonical figure (§3).
- The selected scenario's outputs equal the Forecast's.
- The balance sheet balances in every period that matters.
- No error values on any model tab (one `SUMPRODUCT(--ISERROR(...))` row).

Warnings such as cash going negative are business results, not model
errors. A reader who tries a harsh scenario should see WARN, while the
badge stays "Model ties: OK".

**Don't plug.** When a check fails, find the cause and report it. Never
type a number, or add a balancing row, to turn a FAIL into a PASS. If
the cause can't be found, leave the badge on CHECK and say so.
