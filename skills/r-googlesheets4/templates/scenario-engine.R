# scenario-engine.R — Source/Override/Effective row pattern with reconciliation
#
# Demonstrates the finance-model patterns from references/finance-models.md:
# - Source/Override/Effective 3-row blocks
# - Sheet-time gating via a single named cell
# - Reconciliation block with Δ row
# - Anchor cells + audit row
#
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
ROW_CONFIG_LAST_ACTUAL <- 2L
COL_CONFIG_VAL <- 19L     # col S — single named cell for "last actual month"

# Source / Override / Effective row positions (header + 3 rows × 3 metrics)
R <- list(
  rev_hdr = 5L, rev_src = 6L, rev_ovr = 7L, rev_eff = 8L,
  cogs_hdr = 10L, cogs_src = 11L, cogs_ovr = 12L, cogs_eff = 13L,
  opex_hdr = 15L, opex_src = 16L, opex_ovr = 17L, opex_eff = 18L,
  reconc_hdr = 21L, reconc_total = 22L, reconc_canon = 23L, reconc_delta = 24L
)

# ── Create the workbook ──
ss <- gs_open_or_create("Scenario Engine Demo", c(TAB_SD, TAB_DOWN))
sid_sd   <- get_sheet_id(ss, TAB_SD)
sid_down <- get_sheet_id(ss, TAB_DOWN)

# ── Step 1: write Source/Override/Effective blocks on Source Data tab ──
sd_make_soe <- function(hdr_row, src_row, ovr_row, eff_row, label, source_fn) {
  write_cell(ss, TAB_SD, hdr_row, COL_LABEL, label)
  write_cell(ss, TAB_SD, src_row, COL_LABEL, "  Source")
  write_cell(ss, TAB_SD, ovr_row, COL_LABEL, "  Override (yellow)")
  write_cell(ss, TAB_SD, eff_row, COL_LABEL, "  Effective")
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
sd_make_soe(R$rev_hdr,  R$rev_src,  R$rev_ovr,  R$rev_eff,
            "Revenue",  function(i) sprintf("=%d * 100000", i))
sd_make_soe(R$cogs_hdr, R$cogs_src, R$cogs_ovr, R$cogs_eff,
            "COGS",     function(i) sprintf("=-%d * 30000", i))
sd_make_soe(R$opex_hdr, R$opex_src, R$opex_ovr, R$opex_eff,
            "OPEX",     function(i) sprintf("=-%d * 20000", i))

# Config: single named cell for "last actual month" (1-12)
write_cell(ss, TAB_SD, ROW_CONFIG_LAST_ACTUAL, COL_LABEL, "Last actual month (1-12)")
write_cell(ss, TAB_SD, ROW_CONFIG_LAST_ACTUAL, COL_CONFIG_VAL, 3L)

flush_writes(ss)
Sys.sleep(2)

# Create the named range AFTER values are committed, BEFORE downstream formulas
batch_format(ss, list(
  fmt_named_range(sid_sd, "last_actual_month",
                  ROW_CONFIG_LAST_ACTUAL, ROW_CONFIG_LAST_ACTUAL,
                  COL_CONFIG_VAL, COL_CONFIG_VAL)
))

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

write_cell(ss, TAB_DOWN, 1, COL_LABEL, "Engine — Effective + gated growth")
for (i in seq_along(MONTH_COLS)) {
  c2 <- MONTH_COLS[i]
  rev_factor <- sprintf("IF(%d>last_actual_month,%s,1)", i, GROWTH_RATE)

  write_cell(ss, TAB_DOWN, 4, c2, sprintf("=%s * %s", eff_ref("rev", i), rev_factor))
  write_cell(ss, TAB_DOWN, 5, c2, sprintf("=%s", eff_ref("cogs", i)))
  write_cell(ss, TAB_DOWN, 6, c2, sprintf("=%s", eff_ref("opex", i)))
  write_cell(ss, TAB_DOWN, 7, c2, sprintf("=SUM(%s%d:%s%d)",
                                          col_letter(c2), 4L, col_letter(c2), 6L))
  write_cell(ss, TAB_DOWN, 8, c2,
             sprintf('=IF(%d>last_actual_month,"Forecast","Actual")', i))
}

write_cell(ss, TAB_DOWN, 4, COL_LABEL, "Revenue (gated)")
write_cell(ss, TAB_DOWN, 5, COL_LABEL, "COGS")
write_cell(ss, TAB_DOWN, 6, COL_LABEL, "OPEX")
write_cell(ss, TAB_DOWN, 7, COL_LABEL, "Net Income")
write_cell(ss, TAB_DOWN, 8, COL_LABEL, "A/F flag")

# ── Step 3: reconciliation block on Source Data tab ──
write_cell(ss, TAB_SD, R$reconc_hdr,    COL_LABEL, "Reconciliation")
write_cell(ss, TAB_SD, R$reconc_total,  COL_LABEL, "(=) Total Net (Engine)")
write_cell(ss, TAB_SD, R$reconc_total,  17L,
           sprintf("=SUM('%s'!%s7:%s7)", TAB_DOWN,
                   col_letter(MONTH_COLS[1]), col_letter(MONTH_COLS[length(MONTH_COLS)])))
write_cell(ss, TAB_SD, R$reconc_canon,  COL_LABEL, "Canonical (sum eff rows)")
write_cell(ss, TAB_SD, R$reconc_canon,  17L,
           sprintf("=SUM(%s%d:%s%d)+SUM(%s%d:%s%d)+SUM(%s%d:%s%d)",
                   col_letter(MONTH_COLS[1]), R$rev_eff,
                   col_letter(MONTH_COLS[length(MONTH_COLS)]), R$rev_eff,
                   col_letter(MONTH_COLS[1]), R$cogs_eff,
                   col_letter(MONTH_COLS[length(MONTH_COLS)]), R$cogs_eff,
                   col_letter(MONTH_COLS[1]), R$opex_eff,
                   col_letter(MONTH_COLS[length(MONTH_COLS)]), R$opex_eff))
write_cell(ss, TAB_SD, R$reconc_delta,  COL_LABEL, "Δ (should be 0; >0 means revenue gating applied)")
write_cell(ss, TAB_SD, R$reconc_delta,  17L,
           sprintf("=Q%d-Q%d", R$reconc_total, R$reconc_canon))

flush_writes(ss)
Sys.sleep(2)

# ── Step 4: format both tabs ──
batch_format(ss, list(
  fmt_gridlines(sid_sd,   show = FALSE),
  fmt_gridlines(sid_down, show = FALSE),
  fmt_freeze(sid_sd,   rows = 1, cols = 4),
  fmt_freeze(sid_down, rows = 1, cols = 4),

  # Yellow override rows
  fmt_cells(sid_sd, R$rev_ovr,  R$rev_ovr,  COL_LABEL, 16L,
            bg_color = hex_to_color("FFF9C4")),
  fmt_cells(sid_sd, R$cogs_ovr, R$cogs_ovr, COL_LABEL, 16L,
            bg_color = hex_to_color("FFF9C4")),
  fmt_cells(sid_sd, R$opex_ovr, R$opex_ovr, COL_LABEL, 16L,
            bg_color = hex_to_color("FFF9C4")),

  # Effective rows: bold
  apply_style(sid_sd, R$rev_eff,  R$rev_eff,  COL_LABEL, 16L, list(bold = TRUE)),
  apply_style(sid_sd, R$cogs_eff, R$cogs_eff, COL_LABEL, 16L, list(bold = TRUE)),
  apply_style(sid_sd, R$opex_eff, R$opex_eff, COL_LABEL, 16L, list(bold = TRUE)),

  # Reconciliation Δ row
  apply_style(sid_sd, R$reconc_delta, R$reconc_delta, COL_LABEL, 17L,
              STYLE_NET_INCOME),

  # Currency format on month cols (both tabs)
  fmt_cells(sid_sd, R$rev_src, R$opex_eff, MONTH_COLS[1], MONTH_COLS[length(MONTH_COLS)],
            numfmt_type = NUMFMT_CURRENCY$type, numfmt_pattern = NUMFMT_CURRENCY$pattern),
  fmt_cells(sid_down, 4, 7, MONTH_COLS[1], MONTH_COLS[length(MONTH_COLS)],
            numfmt_type = NUMFMT_CURRENCY$type, numfmt_pattern = NUMFMT_CURRENCY$pattern),

  # Tab colors
  fmt_tab_color(sid_down, hex_to_color("2457C5"))
))

cat("Sheet:", gs4_browse(ss), "\n")
cat("Try: change Source Data!S2 (last_actual_month) from 3 to 6 → Engine!8:8 row flips Apr-Jun to Actual.\n")
