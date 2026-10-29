# scenario-engine.R — Source/Override/Effective row pattern with reconciliation
#
# Demonstrates the finance-model patterns from references/finance-models.md:
# - Source/Override/Effective 3-row blocks
# - Sheet-time gating via a single named cell
# - Reconciliation block with Δ row
# - Anchor cells + audit row
# - The finance colour code (§9): inputs blue on pale blue, same-tab formulas
#   black, formulas that pull from another tab green
#
# Styled with the default "Ledger" look (references/design-principles.md).
# Edit the parameters at the top, then run.

USER_EMAIL <- NULL  # NULL = account saved by gs_setup.sh; or "you@example.com"
TAB_SD     <- "Source Data"
TAB_DOWN   <- "Engine"

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
source(file.path(SKILL, "scripts/gs_helpers.R"))
source(file.path(SKILL, "scripts/gs_buffer.R"))
source(file.path(SKILL, "scripts/gs_qa.R"))
source(file.path(SKILL, "scripts/gs_formulas.R"))

library(tibble)

# ── Connect ── uses the login saved by scripts/gs_setup.sh; never opens a browser
gs_connect(USER_EMAIL)

# ── Layout constants ──
MONTH_COLS <- 5:16        # cols E..P (12 months)
COL_LABEL  <- 3L          # col C
COL_TOTAL  <- 17L         # col Q — full-year figures (reconciliation)
ROW_CONFIG_LAST_ACTUAL <- 5L
COL_CONFIG_VAL <- 4L      # col D — single named cell for "last actual month", next to its label
ROW_HDR    <- 7L          # month headers on both tabs; frozen

# Source / Override / Effective row positions (heading + 3 rows × 3 metrics)
R <- list(
  rev_hdr = 8L,  rev_src = 9L,  rev_ovr = 10L, rev_eff = 11L,
  cogs_hdr = 13L, cogs_src = 14L, cogs_ovr = 15L, cogs_eff = 16L,
  opex_hdr = 18L, opex_src = 19L, opex_ovr = 20L, opex_eff = 21L,
  reconc_hdr = 23L, reconc_total = 24L, reconc_canon = 25L, reconc_delta = 26L
)
E <- list(rev = 8L, cogs = 9L, opex = 10L, net = 11L, flag = 12L)   # Engine rows
OVR_ROWS <- c(R$rev_ovr, R$cogs_ovr, R$opex_ovr)
M_LAST <- MONTH_COLS[length(MONTH_COLS)]
M1 <- col_letter(MONTH_COLS[1]); M12 <- col_letter(M_LAST)

# ── Create the workbook ──
ss <- gs_open_or_create("Scenario Engine Demo", c(TAB_SD, TAB_DOWN))
gs_reset_tabs(ss, c(TAB_SD, TAB_DOWN))   # a rerun (SHEET_ID=<id>) starts clean: re-adding the named range would 400
sid_sd   <- get_sheet_id(ss, TAB_SD)
sid_down <- get_sheet_id(ss, TAB_DOWN)

# Title (row 1), finding (row 2), meta + colour key (row 3), month headers (ROW_HDR):
# the same top on both tabs. The key cells are styled exactly like what they explain.
tab_top <- function(tab, title, meta) {
  write_cell(ss, tab, 1, COL_LABEL, title)
  write_cell(ss, tab, 3, COL_LABEL, meta)
  write_block(ss, tab, 3, MONTH_COLS[1], rbind(c("Input", "Formula", "From another tab")))
  write_cell(ss, tab, ROW_HDR, COL_LABEL, "Line item")
  write_block(ss, tab, ROW_HDR, MONTH_COLS[1], rbind(paste("Month", seq_along(MONTH_COLS))))
}
tab_top(TAB_SD,   "Source data", "$ · sample source formulas")
tab_top(TAB_DOWN, "Engine",      "$ · Effective rows + gated growth")
write_cell(ss, TAB_SD, ROW_HDR, COL_TOTAL, "Full year")

# ── Step 1: write Source/Override/Effective blocks on Source Data tab ──
sd_make_soe <- function(hdr_row, src_row, ovr_row, eff_row, label, source_fn) {
  write_cell(ss, TAB_SD, hdr_row, COL_LABEL, label)
  write_cell(ss, TAB_SD, src_row, COL_LABEL, "Source")
  write_cell(ss, TAB_SD, ovr_row, COL_LABEL, "Override (blue: type to replace)")
  write_cell(ss, TAB_SD, eff_row, COL_LABEL, "Effective")
  for (i in seq_along(MONTH_COLS)) {
    c2 <- MONTH_COLS[i]; cl <- col_letter(c2)
    write_cell(ss, TAB_SD, src_row, c2, source_fn(i))
    write_cell(ss, TAB_SD, ovr_row, c2, "")
    write_cell(ss, TAB_SD, eff_row, c2,
               sprintf("=IF(ISNUMBER(%s%d),%s%d,%s%d)",
                       cl, ovr_row, cl, ovr_row, cl, src_row))
  }
}

# Source formulas — placeholder; in real use these come from SUMIFS over raw-data tabs
# (then colour them COL_LINK_FG: they pull from another tab)
sd_make_soe(R$rev_hdr,  R$rev_src,  R$rev_ovr,  R$rev_eff,
            "Revenue",  function(i) sprintf("=%d * 100000", i))
sd_make_soe(R$cogs_hdr, R$cogs_src, R$cogs_ovr, R$cogs_eff,
            "COGS",     function(i) sprintf("=-%d * 30000", i))
sd_make_soe(R$opex_hdr, R$opex_src, R$opex_ovr, R$opex_eff,
            "OPEX",     function(i) sprintf("=-%d * 20000", i))

# One sample override (month 2 revenue), so the pattern shows: input look + "[override]" note
OVR_SAMPLE <- c(R$rev_ovr, MONTH_COLS[2])
write_cell(ss, TAB_SD, OVR_SAMPLE[1], OVR_SAMPLE[2], 250000)

# Config: single named cell for "last actual month" (1-12)
write_cell(ss, TAB_SD, ROW_CONFIG_LAST_ACTUAL, COL_LABEL, "Last actual month (1-12)")
write_cell(ss, TAB_SD, ROW_CONFIG_LAST_ACTUAL, COL_CONFIG_VAL, 3L)

flush_writes(ss)
Sys.sleep(2)

# Theme (font, chart colours) once per file, and the named range AFTER values are
# committed, BEFORE downstream formulas
batch_format(ss, list(
  do.call(fmt_theme_colors, THEME_DEFAULT),
  fmt_named_range(sid_sd, "last_actual_month",
                  ROW_CONFIG_LAST_ACTUAL, ROW_CONFIG_LAST_ACTUAL,
                  COL_CONFIG_VAL, COL_CONFIG_VAL)
), strict = TRUE)

# ── Step 2: downstream Engine tab uses Effective rows + sheet-time gating ──
SH_SD <- sprintf("'%s'", TAB_SD)

eff_ref <- function(line_type, m_idx) {
  row <- switch(line_type,
                rev  = R$rev_eff,
                cogs = R$cogs_eff,
                opex = R$opex_eff)
  sprintf("%s!%s%d", SH_SD, col_letter(MONTH_COLS[m_idx]), row)
}

# Gating: forecast months scale revenue by 5%, actual months don't.
GROWTH_RATE <- "1.05"

for (i in seq_along(MONTH_COLS)) {
  c2 <- MONTH_COLS[i]
  rev_factor <- sprintf("IF(%d>last_actual_month,%s,1)", i, GROWTH_RATE)

  write_cell(ss, TAB_DOWN, E$rev,  c2, sprintf("=%s * %s", eff_ref("rev", i), rev_factor))
  write_cell(ss, TAB_DOWN, E$cogs, c2, sprintf("=%s", eff_ref("cogs", i)))
  write_cell(ss, TAB_DOWN, E$opex, c2, sprintf("=%s", eff_ref("opex", i)))
  write_cell(ss, TAB_DOWN, E$net,  c2, sprintf("=SUM(%s%d:%s%d)",
                                               col_letter(c2), E$rev, col_letter(c2), E$opex))
  write_cell(ss, TAB_DOWN, E$flag, c2,
             sprintf('=IF(%d>last_actual_month,"Forecast","Actual")', i))
}

write_cell(ss, TAB_DOWN, E$rev,  COL_LABEL, "Revenue (gated)")
write_cell(ss, TAB_DOWN, E$cogs, COL_LABEL, "COGS")
write_cell(ss, TAB_DOWN, E$opex, COL_LABEL, "OPEX")
write_cell(ss, TAB_DOWN, E$net,  COL_LABEL, "Net income")
write_cell(ss, TAB_DOWN, E$flag, COL_LABEL, "A/F flag")
write_cell(ss, TAB_DOWN, 2, COL_LABEL,   # the finding: a live formula, so it never goes stale
           sprintf('="Net income is "&TEXT(SUM(%s%d:%s%d),"$#,##0")&" for the year; months after "&last_actual_month&" are forecast, revenue x %s."',
                   M1, E$net, M12, E$net, GROWTH_RATE))

# ── Step 3: reconciliation block on Source Data tab ──
write_cell(ss, TAB_SD, R$reconc_hdr,    COL_LABEL, "Reconciliation")
write_cell(ss, TAB_SD, R$reconc_total,  COL_LABEL, "Total net, from Engine")
write_cell(ss, TAB_SD, R$reconc_total,  COL_TOTAL,
           sprintf("=SUM('%s'!%s%d:%s%d)", TAB_DOWN, M1, E$net, M12, E$net))
write_cell(ss, TAB_SD, R$reconc_canon,  COL_LABEL, "Canonical (sum of Effective rows)")
write_cell(ss, TAB_SD, R$reconc_canon,  COL_TOTAL,
           sprintf("=SUM(%s%d:%s%d)+SUM(%s%d:%s%d)+SUM(%s%d:%s%d)",
                   M1, R$rev_eff, M12, R$rev_eff, M1, R$cogs_eff, M12, R$cogs_eff,
                   M1, R$opex_eff, M12, R$opex_eff))
write_cell(ss, TAB_SD, R$reconc_delta,  COL_LABEL, "Δ (0 = ties; > 0 = revenue gating applied)")
write_cell(ss, TAB_SD, R$reconc_delta,  COL_TOTAL,
           sprintf("=Q%d-Q%d", R$reconc_total, R$reconc_canon))
write_cell(ss, TAB_SD, 2, COL_LABEL,
           sprintf('="Months 1-"&last_actual_month&" are actuals; "&COUNT(%s)&" override(s) in use; the reconciliation Δ is "&TEXT(Q%d,"$#,##0")&"."',
                   paste(sprintf("%s%d:%s%d", M1, OVR_ROWS, M12, OVR_ROWS), collapse = ","), R$reconc_delta))

flush_writes(ss)
Sys.sleep(2)

# ── Step 4: format both tabs ──
# Title block on COL_LABEL (fmt_tab_base's own title rows sit in column B).
title_rows <- function(sid) list(
  apply_style(sid, 1, 1, COL_LABEL, COL_LABEL, STYLE_TITLE),   fmt_row_height(sid, 1, 1, 36L),
  apply_style(sid, 2, 2, COL_LABEL, COL_LABEL, STYLE_FINDING), fmt_row_height(sid, 2, 2, 22L),
  apply_style(sid, 3, 3, COL_LABEL, COL_LABEL, STYLE_NOTE),    fmt_row_height(sid, 3, 3, 18L),
  fmt_row_height(sid, 4, 4, 12L), fmt_row_height(sid, ROW_HDR - 1L, ROW_HDR - 1L, 12L),
  apply_style(sid, 3, 3, MONTH_COLS[1], MONTH_COLS[3], STYLE_NOTE),        # colour key
  apply_style(sid, 3, 3, MONTH_COLS[1], MONTH_COLS[1], STYLE_INPUT),
  fmt_cells(sid, 3, 3, MONTH_COLS[2], MONTH_COLS[2], font_color = COL_FORMULA_FG),
  fmt_cells(sid, 3, 3, MONTH_COLS[3], MONTH_COLS[3], font_color = COL_LINK_FG))
# Model grid: A 16 | B 16 | C label 240 | D 64 | E..P months 88 | Q full year 96 | R 16
WIDTHS <- c(16, 240, 64, rep(88, 12), 96)
END_COL <- 18L
month_hdr <- function(sid, end) fmt_section(sid, ROW_HDR, COL_LABEL, end, heading = FALSE,
                                            numeric_cols = intersect(c(MONTH_COLS, COL_TOTAL), COL_LABEL:end))

sd_fmt <- c(
  fmt_tab_base(sid_sd, 30, END_COL, "model", widths = WIDTHS, title_row = NULL, inputs = TRUE,
               freeze_rows = ROW_HDR),   # rows only: a frozen column would clip the finding; blue tab: inputs
  title_rows(sid_sd), month_hdr(sid_sd, COL_TOTAL),
  list(apply_style(sid_sd, ROW_CONFIG_LAST_ACTUAL, ROW_CONFIG_LAST_ACTUAL,
                   COL_CONFIG_VAL, COL_CONFIG_VAL, STYLE_INPUT, halign = "RIGHT"))
)
for (b in list(R[c("rev_hdr", "rev_src", "rev_eff")], R[c("cogs_hdr", "cogs_src", "cogs_eff")],
               R[c("opex_hdr", "opex_src", "opex_eff")])) {
  sd_fmt <- c(sd_fmt,
    fmt_section(sid_sd, b[[1]], COL_LABEL, COL_TOTAL, header = FALSE),
    fmt_table_body(sid_sd, b[[2]], b[[3]], COL_LABEL, COL_TOTAL, numeric_cols = MONTH_COLS,
                   numfmt = NUMFMT_CURRENCY, subtotal_rows = b[[3]]),        # Effective: bold, rule above
    list(fmt_row_height(sid_sd, b[[3]] + 1L, b[[3]] + 1L, 12L)))
}
sd_fmt <- c(sd_fmt,
  # Override rows: the input look (one look for every typed-in cell) + "[override]" on a used one
  lapply(OVR_ROWS, function(r) apply_style(sid_sd, r, r, MONTH_COLS[1], M_LAST, STYLE_INPUT)),
  list(fmt_note(sid_sd, OVR_SAMPLE[1], OVR_SAMPLE[2], "[override] Sample value. Clear the cell to use the source again.")),
  # Reconciliation: Δ is the total row (ink rule above, double rule below)
  fmt_section(sid_sd, R$reconc_hdr, COL_LABEL, COL_TOTAL, header = FALSE),
  fmt_table_body(sid_sd, R$reconc_total, R$reconc_delta, COL_LABEL, COL_TOTAL,
                 numeric_cols = COL_TOTAL, numfmt = NUMFMT_CURRENCY, total_rows = R$reconc_delta),
  list(fmt_cells(sid_sd, R$reconc_total, R$reconc_total, COL_TOTAL, COL_TOTAL, font_color = COL_LINK_FG))
)

down_fmt <- c(
  fmt_tab_base(sid_down, 20, END_COL, "model", widths = WIDTHS, title_row = NULL,
               freeze_rows = ROW_HDR),   # no inputs: no tab colour
  title_rows(sid_down), month_hdr(sid_down, M_LAST),       # no full-year column here
  fmt_table_body(sid_down, E$rev, E$net, COL_LABEL, M_LAST, numeric_cols = MONTH_COLS,
                 numfmt = NUMFMT_CURRENCY, total_rows = E$net),
  list(fmt_row_height(sid_down, 4, ROW_HDR - 1L, 12L),
       fmt_cells(sid_down, E$rev, E$opex, MONTH_COLS[1], M_LAST,
                 font_color = COL_LINK_FG),                              # pulled from Source Data
       apply_style(sid_down, E$flag, E$flag, COL_LABEL, M_LAST, STYLE_NOTE),
       fmt_cells(sid_down, E$flag, E$flag, MONTH_COLS[1], M_LAST, halign = "RIGHT"))
)

batch_format(ss, c(sd_fmt, down_fmt), strict = TRUE)

cat("Sheet:", gs4_browse(ss), "\n")
cat("Try: change Source Data!D5 (last_actual_month) from 3 to 6 → Engine row 12 flips months 4-6 to Actual.\n")
