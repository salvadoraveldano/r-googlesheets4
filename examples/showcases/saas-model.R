# =============================================================================
# saas-model.R - SaaS financial model showcase (SAMPLE DATA)
#
# Builds   An 8-tab, driver-based, 24-month SaaS model in one Google Sheet:
#          Summary (dashboard: live finding, KPI strip, scenario comparison,
#          ARR-by-scenario chart, MRR waterfall, monthly MRR movements, annual
#          snapshot), Assumptions (Base / Upside / Downside scenario table),
#          Forecast, MRR Bridge, Cohorts (retention heatmap and curves), Unit
#          Economics, Scenarios (all three scenarios computed side by side,
#          straight from the Assumptions columns) and Checks. One scenario cell
#          on Summary drives the whole model through named ranges. Styled with
#          the skill's default "Ledger" design system and the finance colour code
#          (blue inputs, black formulas, green links to another tab).
# Rerun    SHEET_ID=<id> GS_SKILL_DIR=/path/to/skills/r-googlesheets4 \
#              Rscript examples/showcases/saas-model.R
#          (leave SHEET_ID unset to create a new file; the id is printed.
#          Safety: a rerun clears the 8 tabs of that file, so gs_open_or_create() stops before
#          changing anything when SHEET_ID is a file with another title that lacks these tabs,
#          or with a locale other than en_US.)
# Reads    Nothing external. All data is synthetic and generated here (set.seed).
# Access   Default 'sheets' level (spreadsheets scope only). No Drive calls, no
#          sharing, no installs. Needs the login saved by scripts/gs_setup.sh.
# Credit   Built with the r-googlesheets4 skill, on googlesheets4 (Jennifer Bryan),
#          gargle (Jennifer Bryan, Craig Citro, Hadley Wickham) and googledrive (Lucy
#          D'Agostino McGowan, Jennifer Bryan); all Posit Software, PBC
#          (https://googlesheets4.tidyverse.org).
# =============================================================================

# -- Parameters ---------------------------------------------------------------
USER_EMAIL  <- NULL                               # NULL = account saved by gs_setup.sh
SHEET_TITLE <- "SaaS Financial Model - Sample Data"
FIRST_MONTH <- "2027-01-01"                       # first forecast month (an input in the sheet)
SEED        <- 42L                                # seeds the synthetic cohort-quality inputs
REPO_URL    <- "https://github.com/salvadoraveldano/r-googlesheets4"
DOCS_URL    <- "https://googlesheets4.tidyverse.org"

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")          # the skill directory (default: run from it)
if (!file.exists(file.path(SKILL, "scripts", "gs_helpers.R")))
  stop("Set GS_SKILL_DIR to the skill directory (the one holding scripts/gs_helpers.R); got '", SKILL, "'.", call. = FALSE)
for (f in c("gs_helpers.R", "gs_buffer.R", "gs_qa.R", "gs_formulas.R", "gs_charts.R",
            "gs_modern.R", "brand.R"))
  source(file.path(SKILL, "scripts", f))

# -- Number formats (colours, type and rules come from the Ledger tokens) -------
NF <- function(p, type = "NUMBER") list(type = type, pattern = p)   # a custom number format, as fmt_cells(numfmt = ) takes it
NF_K      <- NUMFMT_CURRENCY_K                    # $1,234K; model grids: negatives in parentheses, no red
NF_K1     <- NF('$#,##0.0,"K";($#,##0.0,"K");"-"') # one decimal: contraction is small
NF_USD    <- NUMFMT_CURRENCY
NF_M1     <- NUMFMT_CURRENCY_M1                   # $3.5M (NUMFMT_CURRENCY_M would round it to $4M)
NF_INT    <- NF('#,##0;(#,##0);"-"')
NF_PCT1   <- NF("0.0%;(0.0%)", "PERCENT")
NF_PCT2   <- NF("0.00%", "PERCENT")
NF_PCT0   <- NUMFMT_PCT_WHOLE
NF_DPCT0  <- NF('+0%;-0%;"-"', "PERCENT")
NF_X      <- NF('0.0"x"')
NF_MO     <- NF('0" mo"')
NF_CHK    <- NF("#,##0.00;-#,##0.00;0.00")
NF_AXIS_K <- NF('$#,##0.0,"K";-$#,##0.0,"K";$0')   # one decimal: contraction is a few $K, and the Downside axis steps by 2.5K
NF_AXIS_M <- NF('$#,##0.0,,"M";-$#,##0.0,,"M";$0')   # ARR chart feed: the axis takes this format, so zero reads $0, not "-"
NF_USD0   <- NF('$#,##0;($#,##0);$0')                # waterfall source: the zero tick reads $0, not "-"
GREY <- hex_to_color(CHART_PALETTE[2]); DARK <- hex_to_color(CHART_PALETTE[5])   # comparison series

# -- Layout (pure data; no API calls) -------------------------------------------
TAB <- c(sum = "Summary", asm = "Assumptions", fc = "Forecast", br = "MRR Bridge",
         co = "Cohorts", ue = "Unit Economics", sn = "Scenarios", ck = "Checks")
XB <- "'MRR Bridge'"; XU <- "'Unit Economics'"

# Forecast: one row per key; months run across (D = month 1 ... AA = month 24).
F_KEYS <- c("top", "title", "sub", "meta", "mnum", "hdr",
            "s_drv", "churn", "gm",
            "s_cust", "c_open", "c_new", "c_churn", "c_close",
            "s_mrr", "m_open", "m_new", "m_exp", "m_con", "m_churn", "m_close", "arr",
            "m_growth", "ret_net", "ret_gross",
            "s_pl", "rev", "cogs", "gp", "gm_pct", "sm", "rd", "ga", "opex", "ebitda", "ebitda_pct",
            "s_cash", "cash_open", "cash_flow", "cash_close",
            "s_ue", "arpa", "ltv", "ltv_cac",
            "s_feed", "f_month", "f_new", "f_exp", "f_con", "f_churn", "gap", "note")
r <- as.list(setNames(seq_along(F_KEYS), F_KEYS))      # Forecast row numbers
N_M <- 24L
MN <- r$mnum                                           # row that holds the month number
mcol <- function(t) col_letter(3L + t)                 # column letter of month t
COL_Y1 <- 29L; COL_Y2 <- 30L                           # AC, AD: Year 1 / Year 2 totals
M12 <- mcol(12L); M24 <- mcol(24L)                      # O, AA

U <- list(title = 2, sub = 3, leg = 4, hdr = 5, s_acq = 6, new = 7, cac = 8, arpa = 9, gm = 10,
          s_ltv = 11, churn = 12, life = 13, ltv = 14, ltvcac = 15, payback = 16,
          s_ret = 17, nrr = 18, grr = 19, growth = 20, margin = 21, r40 = 22, magic = 23, note = 25)
# Rules of thumb as numbers (operator, threshold, display format): the Status column tests year 2 against them.
U_RULE <- list(churn = list("<", 0.02, '"< "0%'), ltvcac = list(">=", 3, '">= "0.0"x"'),
               payback = list("<=", 18, '"<= "0" mo"'), nrr = list(">=", 1, '">= "0%'),
               grr = list(">=", 0.8, '">= "0%'), r40 = list(">=", 0.4, '">= "0%'),
               magic = list(">", 0.75, '"> "0.00'))
B <- list(title = 2, sub = 3, leg = 4, hdr = 6, from = 7, to = 8, open = 9, new = 10, exp = 11,
          con = 12, churn = 13, close = 14, net = 15, netpct = 16, tie = 17, diff = 18, note = 20,
          chart = 7, chart_col = 9,                    # chart sits right of the table, below the frozen rows
          feed_hdr = 21L, feed = 22L)                  # waterfall feed: 6 rows, losses before gains (see below)
CO <- list(first = 7L, n = 12L, avg = 19L, hdr = 6L,   # cohort rows 7..18, average row 19
           feed = 25L, chart = 31L)                    # curve feed rows 26..29, chart below it
# Scenarios: three blocks (Base, Upside, Downside), each a heading plus 10 rows, then the ARR chart feed.
SE <- list(mnum = 5L, hdr = 6L, first = 7L, step = 12L, feed = 43L, note = 51L)
SE_K <- c("churn", "new", "cust", "mrr", "arr", "rev", "gm", "ebitda", "cash", "ltvcac")
se_row <- function(s, k) SE$first + (s - 1L) * SE$step + match(k, SE_K)   # s: 1 Base, 2 Upside, 3 Downside
SE_F <- list(date = 44L, base = 45L, up = 46L, down = 47L, sel = 48L, mark = 49L)
SCN <- c("Base", "Upside", "Downside"); SCN_COL <- c("D", "E", "F")       # scenario names, Assumptions columns
# Summary (dashboard grid A16 | B224 | C-E 3x112 | F24 | G-I 3x120 | J152 | K16): KPI strip from row 6, two rows
# of side-by-side blocks (left B-E, right G-J), the monthly movements across the full width, how to use, about.
SU <- list(kpi = 6L, cmp = 11L, cmp_first = 13L, cmp_note = 21L, br = 23L, snap_first = 25L, br_note = 33L,
           mv = 35L, mv_note = 47L, howto = 49L, about = 56L)
K_COLS <- c(2:5, 7:8)                                  # KPI columns; F is the gutter
CTRL <- list(scn = c(2L, 10L), per = c(SU$br, 5L))     # the scenario picker (J2) and the bridge-period picker (E23)
kpi_cell <- function(i) paste0("$", col_letter(K_COLS[i]), "$", SU$kpi + 1L)   # a KPI value cell, absolute A1
# Checks: integrity rows from row 7, then the business warnings.
CK_FIRST <- 7L; N_CK <- 17L; CK_LAST <- CK_FIRST + N_CK - 1L
W_BAR <- CK_LAST + 2L; W_FIRST <- W_BAR + 1L; W_LAST <- W_FIRST + 1L

# Scenario drivers. One row per driver; the named range points at the Live column.
DRV <- tibble::tribble(
  ~group, ~name, ~label, ~unit, ~nf, ~base, ~up, ~down, ~note,
  "Opening position", "start_customers", "Customers at start", "customers", "int", 300, 300, 300, "Paying customers on day 1 of the forecast",
  "Opening position", "start_mrr", "MRR at start", "$ / month", "usd", 120000, 120000, 120000, "Monthly recurring revenue on day 1",
  "Opening position", "start_cash", "Cash at start", "$", "usd", 2000000, 2000000, 2000000, "Cash on hand on day 1",
  "New customers and pricing", "new_cust_start", "New customers in month 1", "customers / month", "int", 12, 14, 10, "New customers signed in the first month",
  "New customers and pricing", "new_cust_growth", "New customer growth", "% / month", "pct", 0.03, 0.04, 0.015, "Month-on-month growth in new customers",
  "New customers and pricing", "arpa_new", "ARPA of new customers", "$ / month", "usd", 400, 430, 370, "Starting MRR of each new customer (ACV = 12x)",
  "Retention", "churn_rate", "Monthly churn rate", "% / month", "pct", 0.016, 0.012, 0.022, "Share of opening customers and MRR lost each month (month 1)",
  "Retention", "churn_improve", "Churn improvement", "% relative / month", "pct", 0.003, 0.005, 0.001, "Relative fall in the churn rate each month as retention matures",
  "Retention", "expansion_rate", "Expansion rate", "% of MRR / month", "pct", 0.02, 0.024, 0.012, "Upsell, as a share of opening MRR",
  "Retention", "contraction_rate", "Contraction rate", "% of MRR / month", "pct", 0.004, 0.003, 0.007, "Downgrades, as a share of opening MRR",
  "Costs and margin", "cac_per_customer", "CAC", "$ / new customer", "usd", 6500, 5800, 7500, "Sales and marketing spend per new customer",
  "Costs and margin", "gross_margin", "Gross margin, month 1", "% of revenue", "pct", 0.74, 0.78, 0.70, "Revenue less cost of revenue, in the first month",
  "Costs and margin", "gm_gain_per_year", "Gross margin gain", "pts / year", "pct", 0.04, 0.05, 0.02, "Margin improvement from scale (percentage points per year)",
  "Costs and margin", "rd_start", "R&D spend, month 1", "$ / month", "usd", 45000, 45000, 45000, "Research and development in the first month",
  "Costs and margin", "ga_start", "G&A spend, month 1", "$ / month", "usd", 25000, 25000, 25000, "General and administrative in the first month",
  "Costs and margin", "opex_growth", "R&D and G&A growth", "% / month", "pct", 0.015, 0.02, 0.01, "Month-on-month growth of R&D and G&A",
  "Model limits (same in every scenario)", "gm_cap", "Gross margin cap", "% of revenue", "pct", 0.95, 0.95, 0.95, "Ceiling on the gross margin as scale lifts it",
  "Model limits (same in every scenario)", "runway_cap", "Runway display cap", "months", "mo", 60, 60, 60, "Runway above this shows as 'N+ mo' on Summary (N = this cap)",
  "Model limits (same in every scenario)", "runway_warn", "Runway warning below", "months", "mo", 12, 12, 12, "Cash runway under this turns red on Summary",
  "Cohorts (illustrative)", "onboard_drop", "Month-1 onboarding drop", "% of cohort", "pct", 0.04, 0.03, 0.06, "Extra loss of a cohort in its first month (Cohorts tab only)")
A_HDR <- 5L; A_BAND <- 6L; A_SCN <- 7L; A_FIRST <- 8L  # Assumptions: header, settings heading, scenario echo, first-month input
A_ROWS <- list(); a_next <- A_FIRST + 1L               # row of each group heading / driver
for (g in unique(DRV$group)) {
  A_ROWS[[paste0("grp_", g)]] <- a_next; a_next <- a_next + 1L
  for (n in DRV$name[DRV$group == g]) { A_ROWS[[n]] <- a_next; a_next <- a_next + 1L }
}
A_LAST <- a_next - 1L

GRID <- list(sum = c(64L, 11L), asm = c(A_LAST + 3L, 9L), fc = c(max(unlist(r)) + 3L, 31L),
             br = c(44L, 14L), co = c(50L, 18L), ue = c(26L, 9L), sn = c(52L, 28L), ck = c(34L, 8L))

# -- Chart titles state what the sample shows ------------------------------------
# A chart title cannot be a formula. Every scenario is simulated here from the same drivers the sheet gets (the
# Scenarios-tab recurrence), so a title on a picker-driven chart is only a finding when it holds in all three.
sim <- lapply(c("base", "up", "down"), function(col) {
  v <- setNames(DRV[[col]], DRV$name); mrr <- v[["start_mrr"]]; arr <- net <- numeric(N_M)
  for (t in seq_len(N_M)) {
    gain <- v[["new_cust_start"]] * (1 + v[["new_cust_growth"]])^(t - 1) * v[["arpa_new"]] + mrr * v[["expansion_rate"]]
    loss <- mrr * (v[["contraction_rate"]] + v[["churn_rate"]] * (1 - v[["churn_improve"]])^(t - 1))
    net[t] <- gain - loss; mrr <- mrr + net[t]; arr[t] <- 12 * mrr
  }
  list(arr = arr, net = net, arr0 = 12 * v[["start_mrr"]])
})
arr24 <- vapply(sim, function(s) s$arr[N_M], 0)
TTL <- list(
  arr = if (all(vapply(sim, function(s) s$arr[N_M] > s$arr0, TRUE)))
          "ARR grows in every scenario"     # no figures: an edited copy would make them false; the end labels carry them
        else "ARR by scenario, month end",
  mv  = if (all(vapply(sim, function(s) all(s$net > 0), TRUE))) "Gains beat losses every month, in every scenario"
        else "MRR gained and lost each month",
  wf  = "Opening to closing MRR for the picked period",
  co  = "Lower-quality cohorts lose customers faster")

# -- Small local helpers ---------------------------------------------------------
# A table's column-header row with no section heading above it; `ink` adds the block's top rule.
col_header <- function(sid, rw, c1, c2, num = integer(0), ink = FALSE)
  c(fmt_section(sid, rw, c1, c2, numeric_cols = num, heading = FALSE),
    if (ink) list(fmt_borders(sid, rw, rw, c1, c2, top = BORDER_INK)))
# The finance colour key in a model tab's meta row: three cells styled exactly like what they explain.
KEY <- c("Input", "Formula", "From another tab")
write_key <- function(tab, rw, c0) for (j in 1:3) write_cell(ss, tab, rw, c0 + j - 1L, KEY[j])
key_fmt <- function(sid, rw, c0) list(
  apply_style(sid, rw, rw, c0, c0, STYLE_INPUT, font_size = 9, halign = "CENTER"),
  fmt_cells(sid, rw, rw, c0 + 1L, c0 + 2L, font_size = 9, font_color = COL_INK),
  fmt_cells(sid, rw, rw, c0 + 2L, c0 + 2L, font_color = COL_LINK_FG))
# A picker: ONE cell in the control look inside an accent box, its 9pt label in the cell to its left.
BOX <- list(style = "SOLID_MEDIUM", color = COL_ACCENT)
control <- function(sid, rw, c0) list(
  apply_style(sid, rw, rw, c0 - 1L, c0 - 1L, STYLE_NOTE, halign = "RIGHT", valign = "MIDDLE"),
  apply_style(sid, rw, rw, c0, c0, STYLE_CONTROL, valign = "MIDDLE"),
  fmt_borders(sid, rw, rw, c0, c0, top = BOX, bottom = BOX, left = BOX, right = BOX))
# The month-number row above a monthly header: muted, with the block's ink rule on top.
mnum_row <- function(sid, rw, c2) list(
  apply_style(sid, rw, rw, 2, c2, STYLE_NOTE, halign = "RIGHT"), fmt_cells(sid, rw, rw, 2, 2, halign = "LEFT"),
  fmt_borders(sid, rw, rw, 2, c2, top = BORDER_INK), fmt_row_height(sid, rw, rw, 18))

# -- Connect, create or reuse the sheet, reset it -------------------------------
gs_connect(USER_EMAIL)
# On a reused SHEET_ID, gs_open_or_create() stops before any change if the title/tabs or the locale do not match.
ss <- gs_open_or_create(SHEET_TITLE, unname(TAB),
                        time_zone = "Etc/GMT", locale = "en_US",       # zone: create only, neutral for a public file; locale: en_US so TEXT() and dates read as expected (set on create, checked on reuse)
                        rows = setNames(vapply(GRID, `[`, 0, 1L), TAB[names(GRID)]),
                        cols = setNames(vapply(GRID, `[`, 0, 2L), TAB[names(GRID)]))
ss_id <- as.character(ss)
props <- googlesheets4::sheet_properties(ss)
sid   <- setNames(as.numeric(props$id[match(TAB, props$name)]), names(TAB))
batch_format(ss, fmt_tab_order(NULL, unname(sid)), strict = TRUE)       # tab order = the order of TAB
gs_reset_tabs(ss, tabs = unname(TAB))                                   # rebuild in place: charts, names, protections, rules, merges, values, formats

# =============================================================================
# 1. VALUES AND FORMULAS (buffered: nothing is sent until flush_writes())
# =============================================================================
## ---- Assumptions ------------------------------------------------------------
asm <- TAB[["asm"]]
write_cell(ss, asm, 2, 2, "Assumptions")
write_cell(ss, asm, 3, 2, '="The model runs on "&scenario&": "&TEXT(new_cust_start,"0")&" new customers in month 1, "&TEXT(churn_rate,"0.0%")&" monthly churn and "&TEXT(arpa_new,"$#,##0")&" ARPA for new customers."')
write_cell(ss, asm, 4, 2, "Sample data · pick the scenario on Summary")
write_key(asm, 4, 4)
for (i in 1:7) write_cell(ss, asm, A_HDR, 1L + i,
                   c("Driver", "In use", "Base", "Upside", "Downside", "Unit", "Notes")[i])
write_cell(ss, asm, A_BAND, 2, "Model settings")
write_cell(ss, asm, A_SCN, 2, "Scenario (change it on Summary)")
write_cell(ss, asm, A_SCN, 3, "=scenario")
write_cell(ss, asm, A_FIRST, 2, "First forecast month")
write_cell(ss, asm, A_FIRST, 3, FIRST_MONTH)
write_cell(ss, asm, A_FIRST, 7, "date"); write_cell(ss, asm, A_FIRST, 8, "Month 1 of the 24-month forecast")
for (g in unique(DRV$group)) write_cell(ss, asm, A_ROWS[[paste0("grp_", g)]], 2, g)
for (i in seq_len(nrow(DRV))) {
  rw <- A_ROWS[[DRV$name[i]]]
  write_cell(ss, asm, rw, 2, DRV$label[i])
  write_cell(ss, asm, rw, 3, sprintf("=IFERROR(INDEX(D%d:F%d,MATCH(scenario,$D$%d:$F$%d,0)),D%d)",
                                 rw, rw, A_HDR, A_HDR, rw))
  write_cell(ss, asm, rw, 4, DRV$base[i]); write_cell(ss, asm, rw, 5, DRV$up[i]); write_cell(ss, asm, rw, 6, DRV$down[i])
  write_cell(ss, asm, rw, 7, DRV$unit[i]); write_cell(ss, asm, rw, 8, DRV$note[i])
}

## ---- Forecast ---------------------------------------------------------------
fc <- TAB[["fc"]]
write_cell(ss, fc, r$title, 2, "Forecast: 24 months, monthly")
write_cell(ss, fc, r$sub, 2, glue('="Closing MRR "&IF({M24}{r$m_close}>=C{r$m_close},"grows","falls")&" from "&TEXT(C{r$m_close},"$#,##0")&" to "&TEXT({M24}{r$m_close},"$#,##0")&" in 24 months; EBITDA "&IFERROR("turns positive in month "&MATCH(TRUE,ARRAYFORMULA(D{r$ebitda}:{M24}{r$ebitda}>0),0),"stays negative")&"."'))
write_cell(ss, fc, r$meta, 2, '="Sample data · "&scenario&" scenario · 24 months from "&TEXT(first_month,"mmmm yyyy")')
write_key(fc, r$meta, 8)
write_cell(ss, fc, r$hdr, 2, "Line item"); write_cell(ss, fc, r$hdr, 3, "Start"); write_cell(ss, fc, r$hdr, COL_Y1, "Year 1"); write_cell(ss, fc, r$hdr, COL_Y2, "Year 2")
write_cell(ss, fc, r$mnum, 2, "Month number"); write_cell(ss, fc, r$mnum, 3, 0L)
SEC <- c(s_drv = "Drivers, live from Assumptions", s_cust = "Customers", s_mrr = "MRR build",
         s_pl = "P&L", s_cash = "Cash", s_ue = "Unit economics by month",
         s_feed = "Chart feed (drives the Summary movements chart; do not edit)")
for (k in names(SEC)) write_cell(ss, fc, r[[k]], 2, SEC[[k]])
LBL <- c(churn = "Monthly churn rate", gm = "Gross margin target", c_open = "Opening customers",
         c_new = "New customers", c_churn = "Churned customers", c_close = "Closing customers",
         m_open = "Opening MRR", m_new = "New MRR", m_exp = "Expansion MRR", m_con = "Contraction MRR",
         m_churn = "Churned MRR", m_close = "Closing MRR", arr = "ARR (closing MRR x 12)",
         m_growth = "MRR growth, month on month", ret_net = "Net MRR retention, monthly",
         ret_gross = "Gross MRR retention, monthly", rev = "Revenue", cogs = "Cost of revenue",
         gp = "Gross profit", gm_pct = "Gross margin %", sm = "Sales and marketing",
         rd = "Research and development", ga = "General and administrative",
         opex = "Total operating expenses", ebitda = "EBITDA", ebitda_pct = "EBITDA margin %",
         cash_open = "Opening cash", cash_flow = "Net cash flow (= EBITDA)", cash_close = "Closing cash",
         arpa = "ARPA, month end ($ per customer)", ltv = "LTV ($)", ltv_cac = "LTV : CAC",
         f_month = "Month of the forecast", f_new = "New MRR", f_exp = "Expansion MRR",
         f_con = "Contraction MRR", f_churn = "Churned MRR")
for (k in names(LBL)) write_cell(ss, fc, r[[k]], 2, LBL[[k]])
FEED_NAME <- c(f_month = "Month", f_new = "New", f_exp = "Expansion",
               f_con = "Contraction", f_churn = "Churn")
for (k in names(FEED_NAME)) write_cell(ss, fc, r[[k]], 3, FEED_NAME[[k]])      # series names for the charts
write_cell(ss, fc, r$c_close, 3, "=start_customers"); write_cell(ss, fc, r$m_close, 3, "=start_mrr")
write_cell(ss, fc, r$arr, 3, glue("=C{r$m_close}*12")); write_cell(ss, fc, r$cash_close, 3, "=start_cash")
write_cell(ss, fc, r$arpa, 3, glue('=IF(C{r$c_close}=0,"",C{r$m_close}/C{r$c_close})'))
write_cell(ss, fc, r$note, 2, "Note: costs are positive and MRR losses negative, in parentheses. Green figures pull from Assumptions; black ones are calculated on this tab. Year columns sum the flows and take the closing balances.")

month_formula <- function(k, t) {
  L <- mcol(t); P <- col_letter(2L + t)
  switch(k,
    hdr       = glue('=TEXT(EDATE(first_month,{L}${MN}-1),"mmm yy")'),
    churn     = glue("=churn_rate*(1-churn_improve)^({L}${MN}-1)"),
    gm        = glue("=MIN(gm_cap,gross_margin+gm_gain_per_year*({L}${MN}-1)/12)"),
    c_open    = glue("={P}{r$c_close}"),
    c_new     = glue("=new_cust_start*(1+new_cust_growth)^({L}${MN}-1)"),            # fractional customers keep the curves smooth
    c_churn   = glue("=-{L}{r$c_open}*{L}{r$churn}"),
    c_close   = glue("=SUM({L}{r$c_open}:{L}{r$c_churn})"),
    m_open    = glue("={P}{r$m_close}"),
    m_new     = glue("={L}{r$c_new}*arpa_new"),
    m_exp     = glue("={L}{r$m_open}*expansion_rate"),
    m_con     = glue("=-{L}{r$m_open}*contraction_rate"),
    m_churn   = glue("=-{L}{r$m_open}*{L}{r$churn}"),
    m_close   = glue("=SUM({L}{r$m_open}:{L}{r$m_churn})"),
    arr       = glue("={L}{r$m_close}*12"),
    m_growth  = glue('=IF({L}{r$m_open}=0,"",{L}{r$m_close}/{L}{r$m_open}-1)'),
    ret_net   = glue('=IF({L}{r$m_open}=0,"",1+({L}{r$m_exp}+{L}{r$m_con}+{L}{r$m_churn})/{L}{r$m_open})'),
    ret_gross = glue('=IF({L}{r$m_open}=0,"",1+({L}{r$m_con}+{L}{r$m_churn})/{L}{r$m_open})'),
    rev       = glue("=AVERAGE({L}{r$m_open},{L}{r$m_close})"),
    cogs      = glue("={L}{r$rev}*(1-{L}{r$gm})"),
    gp        = glue("={L}{r$rev}-{L}{r$cogs}"),
    gm_pct    = glue('=IF({L}{r$rev}=0,"",{L}{r$gp}/{L}{r$rev})'),
    sm        = glue("={L}{r$c_new}*cac_per_customer"),
    rd        = glue("=rd_start*(1+opex_growth)^({L}${MN}-1)"),
    ga        = glue("=ga_start*(1+opex_growth)^({L}${MN}-1)"),
    opex      = glue("=SUM({L}{r$sm}:{L}{r$ga})"),
    ebitda    = glue("={L}{r$gp}-{L}{r$opex}"),
    ebitda_pct= glue('=IF({L}{r$rev}=0,"",{L}{r$ebitda}/{L}{r$rev})'),
    cash_open = glue("={P}{r$cash_close}"),
    cash_flow = glue("={L}{r$ebitda}"),
    cash_close= glue("={L}{r$cash_open}+{L}{r$cash_flow}"),
    arpa      = glue('=IF({L}{r$c_close}=0,"",{L}{r$m_close}/{L}{r$c_close})'),
    ltv       = glue('=IFERROR({L}{r$arpa}*{L}{r$gm_pct}/{L}{r$churn},"")'),
    ltv_cac   = glue('=IF({L}{r$ltv}="","",IFERROR({L}{r$ltv}/cac_per_customer,""))'),   # blank LTV (churn 0) stays blank: "" / CAC would read 0
    f_month   = glue('=TEXT({L}${MN},"0")'),           # month number as text: 24 short labels stay flat on a 464 px chart
    f_new     = glue("={L}{r$m_new}"),
    f_exp     = glue("={L}{r$m_exp}"),
    f_con     = glue("={L}{r$m_con}"),
    f_churn   = glue("={L}{r$m_churn}"),
    stop("no month formula for ", k))
}
MONTH_KEYS <- c("hdr", "churn", "gm", "c_open", "c_new", "c_churn", "c_close", "m_open", "m_new", "m_exp",
                "m_con", "m_churn", "m_close", "arr", "m_growth", "ret_net", "ret_gross", "rev", "cogs",
                "gp", "gm_pct", "sm", "rd", "ga", "opex", "ebitda", "ebitda_pct", "cash_open", "cash_flow",
                "cash_close", "arpa", "ltv", "ltv_cac", "f_month", "f_new", "f_exp", "f_con", "f_churn")
for (t in seq_len(N_M)) {
  write_cell(ss, fc, r$mnum, 3L + t, t)
  for (k in MONTH_KEYS) write_cell(ss, fc, r[[k]], 3L + t, month_formula(k, t))
}
year_formula <- function(k, y) {                       # Year 1 = months 1-12, Year 2 = months 13-24
  a <- if (y == 1L) 1L else 13L; A <- mcol(a); Z <- mcol(a + 11L); Y <- col_letter(if (y == 1L) COL_Y1 else COL_Y2)
  switch(k,
    c_new = , c_churn = , m_new = , m_exp = , m_con = , m_churn = , rev = , cogs = , gp = , sm = , rd = ,
    ga = , opex = , ebitda = , cash_flow = glue("=SUM({A}{r[[k]]}:{Z}{r[[k]]})"),
    c_open = , m_open = , cash_open = glue("={A}{r[[k]]}"),
    c_close = , m_close = , arr = , cash_close = , arpa = , ltv = , ltv_cac = glue("={Z}{r[[k]]}"),
    churn = , gm = glue("=AVERAGE({A}{r[[k]]}:{Z}{r[[k]]})"),
    gm_pct = glue('=IF({Y}{r$rev}=0,"",{Y}{r$gp}/{Y}{r$rev})'),
    ebitda_pct = glue('=IF({Y}{r$rev}=0,"",{Y}{r$ebitda}/{Y}{r$rev})'),
    m_growth = glue('=IF({Y}{r$m_open}=0,"",({Y}{r$m_close}/{Y}{r$m_open})^(1/12)-1)'),
    ret_net = , ret_gross = glue("=PRODUCT({A}{r[[k]]}:{Z}{r[[k]]})^(1/12)"),   # geometric mean: still a monthly rate; Unit Economics compounds the 12 months
    NULL)
}
YEAR_KEYS <- setdiff(MONTH_KEYS, c("hdr", "f_month", "f_new", "f_exp", "f_con", "f_churn"))
for (y in 1:2) for (k in YEAR_KEYS) write_cell(ss, fc, r[[k]], if (y == 1L) COL_Y1 else COL_Y2, year_formula(k, y))

## ---- MRR Bridge -------------------------------------------------------------
br <- TAB[["br"]]
write_cell(ss, br, B$title, 2, "MRR bridge")
write_cell(ss, br, B$sub, 2, glue('=IFERROR("MRR "&IF(G{B$net}>=0,"grows ","falls ")&TEXT(ABS(G{B$netpct}),"0%")&" over "&LOWER(bridge_period)&", from "&TEXT(G{B$open},"$#,##0")&" to "&TEXT(G{B$close},"$#,##0")&".","Pick a bridge period on Summary.")'))
write_cell(ss, br, B$leg, 2, '="Sample data · "&scenario&" scenario · pick the scenario and the bridge period on Summary"')
write_key(br, B$leg, 9)
for (j in 1:3) write_cell(ss, br, B$hdr, 2L + j, c("Year 1", "Year 2", "Full period")[j])
write_cell(ss, br, B$hdr, 2, "Component"); write_cell(ss, br, B$hdr, 7, '="Selected: "&bridge_period')
write_cell(ss, br, B$from, 2, "From month"); write_cell(ss, br, B$to, 2, "To month")
for (j in 1:3) { write_cell(ss, br, B$from, 2L + j, c(1, 13, 1)[j]); write_cell(ss, br, B$to, 2L + j, c(12, 24, 24)[j]) }
BL <- c(open = "Opening MRR", new = "New MRR", exp = "Expansion MRR", con = "Contraction MRR",
        churn = "Churned MRR", close = "Closing MRR", net = "Net new MRR",
        netpct = "Net new MRR, % of opening", tie = "Forecast closing MRR (tie-out)",
        diff = "Difference (should be 0)")
for (k in names(BL)) write_cell(ss, br, B[[k]], 2, BL[[k]])
FR_RNG <- function(k) glue("Forecast!$D${r[[k]]}:$AA${r[[k]]}")
for (j in 1:3) {
  L <- col_letter(2L + j)
  write_cell(ss, br, B$open,  2L + j, glue("=INDEX({FR_RNG('m_open')},{L}${B$from})"))
  for (k in c("new", "exp", "con", "churn")) {
    fk <- c(new = "m_new", exp = "m_exp", con = "m_con", churn = "m_churn")[[k]]
    write_cell(ss, br, B[[k]], 2L + j, glue('=SUMIFS({FR_RNG(fk)},Forecast!$D${MN}:$AA${MN},">="&{L}${B$from},Forecast!$D${MN}:$AA${MN},"<="&{L}${B$to})'))
  }
  write_cell(ss, br, B$close,  2L + j, glue("=SUM({L}{B$open}:{L}{B$churn})"))
  write_cell(ss, br, B$net,    2L + j, glue("=SUM({L}{B$new}:{L}{B$churn})"))
  write_cell(ss, br, B$netpct, 2L + j, glue('=IF({L}{B$open}=0,"",{L}{B$net}/{L}{B$open})'))
  write_cell(ss, br, B$tie,    2L + j, glue("=INDEX({FR_RNG('m_close')},{L}${B$to})"))
  write_cell(ss, br, B$diff,   2L + j, glue("=ROUND({L}{B$close}-{L}{B$tie},2)"))
}
for (k in c("from", "to", "open", "new", "exp", "con", "churn", "close", "net", "netpct", "tie", "diff"))
  write_cell(ss, br, B[[k]], 7, glue("=INDEX(C{B[[k]]}:E{B[[k]]},MATCH(bridge_period,$C${B$hdr}:$E${B$hdr},0))"))
write_cell(ss, br, B$note, 2, "Note: Selected repeats the period picked on Summary and feeds both waterfalls. Contraction and churn are negative, in parentheses.")
# Waterfall feed: opening, losses, gains, closing. A native waterfall has no legend or axis control; with losses
# first the highest bars are the gains and the closing level, and the tall middle bars keep their labels clear.
WF_ORDER <- c("open", "churn", "con", "exp", "new", "close")
write_cell(ss, br, B$feed_hdr, 2, "Chart feed (waterfall order: opening, losses, gains, closing; do not edit)")
for (i in seq_along(WF_ORDER)) {
  write_cell(ss, br, B$feed + i - 1L, 2, glue("=B{B[[WF_ORDER[i]]]}")); write_cell(ss, br, B$feed + i - 1L, 3, glue("=G{B[[WF_ORDER[i]]]}"))
}

## ---- Cohorts ----------------------------------------------------------------
co <- TAB[["co"]]
set.seed(SEED)
# Synthetic cohort-quality inputs with a story: cohort 4 had a rough onboarding month, and a new
# onboarding flow lifts quality from cohort 8 on. Higher quality = lower churn.
quality <- 0.85 + 0.01 * seq_len(CO$n) + rnorm(CO$n, 0, 0.03)
quality[4L] <- 0.55; quality[8:CO$n] <- quality[8:CO$n] + 0.30
quality <- round(quality, 2)
q_rng <- glue("$E${CO$first}:$E${CO$avg - 1L}")                                   # live text: it follows the blue quality inputs
write_cell(ss, co, 2, 2, "Cohort retention")
write_cell(ss, co, 3, 2, glue('="The weakest cohort is #"&MATCH(MIN({q_rng}),{q_rng},0)&" (quality "&TEXT(MIN({q_rng}),"0.00")&"), the strongest #"&MATCH(MAX({q_rng}),{q_rng},0)&" ("&TEXT(MAX({q_rng}),"0.00")&"): quality sets how fast each cohort churns."'))
write_cell(ss, co, 4, 2, '="Sample data · "&scenario&" scenario · share of each signup cohort still active, by months since signup"')
write_key(co, 4, 14)
write_cell(ss, co, 5, 6, "Months since signup")
for (j in 1:4) write_cell(ss, co, CO$hdr, 1L + j, c("#", "Cohort", "New customers", "Quality (x)")[j])
for (a in 0:11) write_cell(ss, co, CO$hdr, 6L + a, a)
for (i in seq_len(CO$n)) {
  rw <- CO$first + i - 1L
  write_cell(ss, co, rw, 2, i)
  write_cell(ss, co, rw, 3, glue("=INDEX(Forecast!$D${r$hdr}:$AA${r$hdr},$B{rw})"))
  write_cell(ss, co, rw, 4, glue("=INDEX({FR_RNG('c_new')},$B{rw})"))
  write_cell(ss, co, rw, 5, quality[i])
  for (a in 0:11) {
    L <- col_letter(6L + a)
    write_cell(ss, co, rw, 6L + a, glue('=IF({L}${CO$hdr}>{CO$n}-$B{rw},"",(1-onboard_drop)^MIN(1,{L}${CO$hdr})*(1-MIN(1,churn_rate/MAX(0.05,$E{rw})))^{L}${CO$hdr})'))
  }
}
write_cell(ss, co, CO$avg, 3, "Weighted average"); write_cell(ss, co, CO$avg, 4, glue("=SUM(D{CO$first}:D{CO$avg - 1L})"))
for (a in 0:11) {
  L <- col_letter(6L + a)
  write_cell(ss, co, CO$avg, 6L + a, glue('=IFERROR(SUMPRODUCT($D${CO$first}:$D${CO$avg - 1L},{L}{CO$first}:{L}{CO$avg - 1L})/SUMIF({L}{CO$first}:{L}{CO$avg - 1L},">=0",$D${CO$first}:$D${CO$avg - 1L}),"")'))
}
write_cell(ss, co, CO$avg + 2L, 2, "How to read: each row is the group of customers who signed up in that month. Reading right, the shade shows how many are lost: white is still active, amber to red is gone.")
write_cell(ss, co, CO$avg + 3L, 2, "Empty cells are months that have not happened yet inside the 12-month window. Change the scenario on Summary to see the heatmap move.")
write_cell(ss, co, CO$avg + 4L, 2, "Cohort sizes come from the Forecast. Churn per cohort = scenario churn / quality (blue, 0.05 to 3; the formulas never use less than 0.05): higher quality, lower churn.")
# Retention-curve feed for the chart below: weighted average, best and weakest cohort quality (all 12 months numeric).
write_cell(ss, co, CO$feed, 2, "Chart feed (drives the curves below; do not edit)")
write_cell(ss, co, CO$feed + 1L, 5, "Months")
for (a in 0:11) write_cell(ss, co, CO$feed + 1L, 6L + a, glue("={col_letter(6L + a)}${CO$hdr}"))
write_cell(ss, co, CO$feed + 2L, 5, "Best"); write_cell(ss, co, CO$feed + 3L, 5, "Average"); write_cell(ss, co, CO$feed + 4L, 5, "Weakest")
for (a in 0:11) {
  L <- col_letter(6L + a); mrow <- CO$feed + 1L
  curve <- function(q) glue("=(1-onboard_drop)^MIN(1,{L}${mrow})*(1-MIN(1,churn_rate/MAX(0.05,{q})))^{L}${mrow}")
  write_cell(ss, co, CO$feed + 2L, 6L + a, curve(glue("MAX($E${CO$first}:$E${CO$avg - 1L})")))
  write_cell(ss, co, CO$feed + 3L, 6L + a, glue("={L}{CO$avg}"))
  write_cell(ss, co, CO$feed + 4L, 6L + a, curve(glue("MIN($E${CO$first}:$E${CO$avg - 1L})")))
}

## ---- Unit Economics ---------------------------------------------------------
ue <- TAB[["ue"]]
write_cell(ss, ue, U$title, 2, "Unit economics")
write_cell(ss, ue, U$sub, 2, glue('="In year 2, LTV : CAC is "&IFERROR(TEXT(D{U$ltvcac},"0.0""x"""),"n/a")&" and NRR "&TEXT(D{U$nrr},"0%")&"; "&COUNTIF(G{U$churn}:G{U$magic},"Watch")&" of {length(U_RULE)} benchmarks need watching."'))
write_cell(ss, ue, U$leg, 2, '="Sample data · "&scenario&" scenario · year 1 = month 12, year 2 = month 24"')
write_key(ue, U$leg, 6)
for (j in 1:7) write_cell(ss, ue, U$hdr, 1L + j, c("Metric", "Year 1", "Year 2", "", "Rule of thumb", "Status (year 2)", "How it is calculated")[j])
write_cell(ss, ue, U$s_acq, 2, "Acquisition"); write_cell(ss, ue, U$s_ltv, 2, "Lifetime value"); write_cell(ss, ue, U$s_ret, 2, "Retention and growth")
write_cell(ss, ue, U$note, 2, "Note: every figure is a formula over the Forecast tab. The blue rules of thumb are rough SaaS benchmarks you can change; Status tests year 2 against them.")
UL <- list(
  new = c("New customers in the year", "Sum of new customers over the 12 months"),
  cac = c("CAC ($, equals the input)", "S&M spend / new customers, or the CAC input when there are none"),
  arpa = c("ARPA, month end ($ / month)", "Closing MRR / closing customers"),
  gm = c("Gross margin %", "Gross profit / revenue, in the year-end month"),
  churn = c("Monthly churn rate", "Churn rate in the year-end month"),
  life = c("Customer lifetime (months)", "1 / monthly churn rate"),
  ltv = c("LTV ($)", "ARPA x gross margin / monthly churn rate"),
  ltvcac = c("LTV : CAC", "LTV / CAC"),
  payback = c("CAC payback (months)", "CAC / (ARPA x gross margin)"),
  nrr = c("Net revenue retention (NRR)", "Product of 12 monthly net retention rates, no new customers"),
  grr = c("Gross revenue retention (GRR)", "Product of 12 monthly gross retention rates, no expansion"),
  growth = c("ARR growth, year on year", "Year-end ARR / opening ARR - 1"),
  margin = c("EBITDA margin", "EBITDA / revenue over the year"),
  r40 = c("Rule of 40", "ARR growth + EBITDA margin"),
  magic = c("Magic number (Q4)", "(Q4 revenue - Q3 revenue) x 4 / Q3 sales and marketing"))
for (k in names(UL)) { write_cell(ss, ue, U[[k]], 2, UL[[k]][1]); write_cell(ss, ue, U[[k]], 8, UL[[k]][2]) }
for (k in names(U_RULE)) {                             # rule of thumb as a number, and the status formula that tests year 2
  write_cell(ss, ue, U[[k]], 6, U_RULE[[k]][[2]])
  write_cell(ss, ue, U[[k]], 7, glue('=IF(D{U[[k]]}="","",IF(D{U[[k]]}{U_RULE[[k]][[1]]}$F{U[[k]]},"On track","Watch"))'))
}
for (y in 1:2) {
  cc <- 2L + y; L <- col_letter(cc)
  e <- if (y == 1L) M12 else M24                       # year-end month column on Forecast
  Y <- col_letter(if (y == 1L) COL_Y1 else COL_Y2)
  q4 <- if (y == 1L) c(mcol(10L), mcol(12L)) else c(mcol(22L), mcol(24L))
  q3 <- if (y == 1L) c(mcol(7L), mcol(9L)) else c(mcol(19L), mcol(21L))
  open_arr <- if (y == 1L) glue("Forecast!C{r$arr}") else glue("Forecast!{M12}{r$arr}")
  write_cell(ss, ue, U$new,    cc, glue("=Forecast!{Y}{r$c_new}"))
  write_cell(ss, ue, U$cac,    cc, glue('=IF(Forecast!{Y}{r$c_new}=0,cac_per_customer,Forecast!{Y}{r$sm}/Forecast!{Y}{r$c_new})'))   # no new customers: S&M is 0 too, so show the input, which is what the Forecast uses
  write_cell(ss, ue, U$arpa,   cc, glue("=Forecast!{e}{r$arpa}"))
  write_cell(ss, ue, U$gm,     cc, glue("=Forecast!{e}{r$gm_pct}"))
  write_cell(ss, ue, U$churn,  cc, glue("=Forecast!{e}{r$churn}"))
  write_cell(ss, ue, U$life,   cc, glue('=IFERROR(1/{L}{U$churn},"")'))
  write_cell(ss, ue, U$ltv,    cc, glue('=IFERROR({L}{U$arpa}*{L}{U$gm}/{L}{U$churn},"")'))
  write_cell(ss, ue, U$ltvcac, cc, glue('=IF({L}{U$ltv}="","",IFERROR({L}{U$ltv}/{L}{U$cac},""))'))
  write_cell(ss, ue, U$payback,cc, glue('=IFERROR({L}{U$cac}/({L}{U$arpa}*{L}{U$gm}),"")'))
  a1 <- mcol(if (y == 1L) 1L else 13L)                 # first month of the year on Forecast; `e` is the last
  write_cell(ss, ue, U$nrr,    cc, glue("=PRODUCT(Forecast!{a1}{r$ret_net}:{e}{r$ret_net})"))
  write_cell(ss, ue, U$grr,    cc, glue("=PRODUCT(Forecast!{a1}{r$ret_gross}:{e}{r$ret_gross})"))
  write_cell(ss, ue, U$growth, cc, glue('=IF({open_arr}=0,"",Forecast!{e}{r$arr}/{open_arr}-1)'))
  write_cell(ss, ue, U$margin, cc, glue("=Forecast!{Y}{r$ebitda_pct}"))
  write_cell(ss, ue, U$r40,    cc, glue('=IFERROR({L}{U$growth}+{L}{U$margin},"")'))
  write_cell(ss, ue, U$magic,  cc, glue('=IFERROR((SUM(Forecast!{q4[1]}{r$rev}:{q4[2]}{r$rev})-SUM(Forecast!{q3[1]}{r$rev}:{q3[2]}{r$rev}))*4/SUM(Forecast!{q3[1]}{r$sm}:{q3[2]}{r$sm}),"")'))
}

## ---- Scenarios --------------------------------------------------------------
# All three scenarios, each computed straight from its own Assumptions column (no named ranges,
# no "In use" column) with its own recurrences. Checks proves the selected one equals the Forecast.
sn <- TAB[["sn"]]
arr_m <- function(s) glue('TEXT({M24}{se_row(s, "arr")},"$0.0,,""M""")')
write_cell(ss, sn, 2, 2, "Scenarios")
write_cell(ss, sn, 3, 2, glue('="At month 24, ARR is "&{arr_m(1)}&" in Base, "&{arr_m(2)}&" in Upside and "&{arr_m(3)}&" in Downside."'))
write_cell(ss, sn, 4, 2, '="Sample data · Base, Upside and Downside side by side · selected on Summary: "&scenario')
write_key(sn, 4, 8)
write_cell(ss, sn, SE$hdr, 2, "Line item"); write_cell(ss, sn, SE$hdr, 3, "Start")
write_cell(ss, sn, SE$mnum, 2, "Month number"); write_cell(ss, sn, SE$mnum, 3, 0L)
write_cell(ss, sn, SE$note, 2, "Note: a second calculation of all three scenarios from the Assumptions columns. It feeds the Summary comparison and ARR chart; Checks proves the selected one matches the Forecast.")
for (t in seq_len(N_M)) {
  write_cell(ss, sn, SE$mnum, 3L + t, t)
  write_cell(ss, sn, SE$hdr, 3L + t, glue('=TEXT(EDATE(first_month,{mcol(t)}${SE$mnum}-1),"mmm yy")'))
}
SE_LBL <- c(churn = "Monthly churn rate", new = "New customers", cust = "Closing customers", mrr = "Closing MRR",
            arr = "ARR (closing MRR x 12)", rev = "Revenue", gm = "Gross margin %", ebitda = "EBITDA",
            cash = "Closing cash", ltvcac = "LTV : CAC")
for (s in 1:3) {
  AV <- function(name) glue("Assumptions!${SCN_COL[s]}${A_ROWS[[name]]}")      # this scenario's driver
  R  <- function(k) se_row(s, k)
  write_cell(ss, sn, R("churn") - 1L, 2, SCN[s])                                            # block heading
  for (k in SE_K) write_cell(ss, sn, R(k), 2, SE_LBL[[k]])
  write_cell(ss, sn, R("cust"), 3, glue("={AV('start_customers')}")); write_cell(ss, sn, R("mrr"), 3, glue("={AV('start_mrr')}"))
  write_cell(ss, sn, R("arr"), 3, glue("=C{R('mrr')}*12")); write_cell(ss, sn, R("cash"), 3, glue("={AV('start_cash')}"))
  for (t in seq_len(N_M)) {
    L <- mcol(t); P <- col_letter(2L + t); M <- glue("{L}${SE$mnum}")
    f <- list(
      churn  = glue("={AV('churn_rate')}*(1-{AV('churn_improve')})^({M}-1)"),
      new    = glue("={AV('new_cust_start')}*(1+{AV('new_cust_growth')})^({M}-1)"),
      cust   = glue("={P}{R('cust')}*(1-{L}{R('churn')})+{L}{R('new')}"),
      mrr    = glue("={P}{R('mrr')}*(1+{AV('expansion_rate')}-{AV('contraction_rate')}-{L}{R('churn')})+{L}{R('new')}*{AV('arpa_new')}"),
      arr    = glue("={L}{R('mrr')}*12"),
      rev    = glue("=({P}{R('mrr')}+{L}{R('mrr')})/2"),
      gm     = glue("=MIN({AV('gm_cap')},{AV('gross_margin')}+{AV('gm_gain_per_year')}*({M}-1)/12)"),
      ebitda = glue("={L}{R('rev')}*{L}{R('gm')}-{L}{R('new')}*{AV('cac_per_customer')}-({AV('rd_start')}+{AV('ga_start')})*(1+{AV('opex_growth')})^({M}-1)"),
      cash   = glue("={P}{R('cash')}+{L}{R('ebitda')}"),
      ltvcac = glue('=IFERROR({L}{R("mrr")}/{L}{R("cust")}*{L}{R("gm")}/{L}{R("churn")}/{AV("cac_per_customer")},"")'))
    for (k in SE_K) write_cell(ss, sn, R(k), 3L + t, f[[k]])
  }
}
# Chart feed for the Summary ARR chart: real dates (the axis thins its own ticks), three scenarios,
# the selected one again (drawn on top in the accent) and two year-end markers. Marker cells stay empty elsewhere (a gap, not a zero).
write_cell(ss, sn, SE$feed, 2, "Chart feed (drives the Summary ARR chart; do not edit)")
write_cell(ss, sn, SE_F$date, 3, "Month")
for (s in 1:3) write_cell(ss, sn, c(SE_F$base, SE_F$up, SE_F$down)[s], 3, SCN[s])
write_cell(ss, sn, SE_F$sel, 3, "Selected"); write_cell(ss, sn, SE_F$mark, 3, "Month 12 and 24")
for (t in seq_len(N_M)) {
  L <- mcol(t)
  write_cell(ss, sn, SE_F$date, 3L + t, glue("=EDATE(first_month,{L}${SE$mnum}-1)"))
  for (s in 1:3) write_cell(ss, sn, c(SE_F$base, SE_F$up, SE_F$down)[s], 3L + t, glue("={L}{se_row(s, 'arr')}"))
  write_cell(ss, sn, SE_F$sel, 3L + t, glue("=CHOOSE(MATCH(scenario,Assumptions!$D${A_HDR}:$F${A_HDR},0),{L}{SE_F$base},{L}{SE_F$up},{L}{SE_F$down})"))
  if (t %in% c(12L, 24L)) write_cell(ss, sn, SE_F$mark, 3L + t, glue("={L}{SE_F$sel}"))
}

## ---- Checks -----------------------------------------------------------------
# Integrity checks tie independent calculation paths to each other and feed the badge. Business
# warnings (cash or customers going negative) depend on the inputs a visitor may change, so they
# are listed apart and never turn the model status red.
ck <- TAB[["ck"]]
rng24 <- function(k) glue("Forecast!D{r[[k]]}:{M24}{r[[k]]}")
HDRS <- glue("Assumptions!$D${A_HDR}:$F${A_HDR}")
pick  <- function(col, k) glue("CHOOSE(MATCH(scenario,{HDRS},0),{paste(sprintf('Scenarios!%s%d', col, se_row(1:3, k)), collapse = ',')})")
pick_sum <- function(k) glue("CHOOSE(MATCH(scenario,{HDRS},0),{paste(sprintf('SUM(Scenarios!D%d:%s%d)', se_row(1:3, k), M24, se_row(1:3, k)), collapse = ',')})")
CHECKS <- list(
  list("Scenario selection is valid", glue("=IF(ISNUMBER(MATCH(scenario,{HDRS},0)),1,0)"), "=1", "eq"),
  list("Bridge period selection is valid", glue("=IF(ISNUMBER(MATCH(bridge_period,{XB}!$C${B$hdr}:$E${B$hdr},0)),1,0)"), "=1", "eq"),
  list("Scenarios (selected) = Forecast: closing MRR, month 24", glue("={pick(M24, 'mrr')}"), glue("=Forecast!{M24}{r$m_close}"), "eq"),
  list("Scenarios (selected) = Forecast: closing customers, month 24", glue("={pick(M24, 'cust')}"), glue("=Forecast!{M24}{r$c_close}"), "eq"),
  list("Scenarios (selected) = Forecast: EBITDA, 24 months", glue("={pick_sum('ebitda')}"), glue("=SUM({rng24('ebitda')})"), "eq"),
  list("Scenarios (selected) = Forecast: closing cash, month 24", glue("={pick(M24, 'cash')}"), glue("=Forecast!{M24}{r$cash_close}"), "eq"),
  list("Scenarios (selected) = Forecast: LTV : CAC, month 24", glue("={pick(M24, 'ltvcac')}"), glue("=Forecast!{M24}{r$ltv_cac}"), "eq"),
  list("MRR bridge Year 1 closes at Forecast month 12", glue("={XB}!C{B$close}"), glue("=Forecast!{M12}{r$m_close}"), "eq"),
  list("MRR bridge Year 2 closes at Forecast month 24", glue("={XB}!D{B$close}"), glue("=Forecast!{M24}{r$m_close}"), "eq"),
  list("MRR bridge full period closes at Forecast month 24", glue("={XB}!E{B$close}"), glue("=Forecast!{M24}{r$m_close}"), "eq"),
  list("MRR bridge: Year 1 + Year 2 net new MRR = full period", glue("={XB}!C{B$net}+{XB}!D{B$net}"), glue("={XB}!E{B$net}"), "eq"),
  list("Waterfall (selected period) closing ties to the Forecast", glue("={XB}!G{B$close}"), glue("={XB}!G{B$tie}"), "eq"),
  list("Cohort sizes = new customers, months 1-12", glue("=SUM(Cohorts!D{CO$first}:D{CO$avg - 1L})"), glue("=SUM(Forecast!D{r$c_new}:{M12}{r$c_new})"), "eq"),
  list("Revenue: Year 1 + Year 2 = sum of 24 months", glue("=Forecast!AC{r$rev}+Forecast!AD{r$rev}"), glue("=SUM({rng24('rev')})"), "eq"),
  list("Summary ARR figure = Forecast ARR, month 24", paste0("=Summary!", gsub("$", "", kpi_cell(1), fixed = TRUE)), glue("=Forecast!{M24}{r$arr}"), "eq"),
  list("Unit Economics LTV : CAC = Forecast LTV : CAC, month 24", glue("={XU}!D{U$ltvcac}"), glue("=Forecast!{M24}{r$ltv_cac}"), "eq"),
  list("No error values on any model tab (Summary included)",   # Summary!J4 (the badge) is left out: it reads this check
       glue("=SUMPRODUCT(--ISERROR(Forecast!A1:AD{max(unlist(r))}))+SUMPRODUCT(--ISERROR({XB}!A1:G{B$feed + 5L}))+SUMPRODUCT(--ISERROR(Cohorts!A1:Q{CO$feed + 4L}))+SUMPRODUCT(--ISERROR({XU}!A1:H{U$magic}))+SUMPRODUCT(--ISERROR(Assumptions!A1:H{A_LAST}))+SUMPRODUCT(--ISERROR(Scenarios!A1:AA{SE_F$mark}))+SUMPRODUCT(--ISERROR(Summary!B2:I4))+SUMPRODUCT(--ISERROR(Summary!B6:J{SU$about + 6L}))"), "=0", "eq"))
WARNS <- list(
  list("Cash stays positive (lowest month-end balance)", glue("=MIN(Forecast!C{r$cash_close}:{M24}{r$cash_close})"), "=0", "ge"),
  list("Customer count stays positive (lowest month-end)", glue("=MIN(Forecast!C{r$c_close}:{M24}{r$c_close})"), "=0", "ge"))
stopifnot(length(CHECKS) == N_CK, length(WARNS) == W_LAST - W_FIRST + 1L)
CK_RNG <- glue("G{CK_FIRST}:G{CK_LAST}")
write_cell(ss, ck, 2, 2, "Model checks")
write_cell(ss, ck, 3, 2, glue('=COUNTIF({CK_RNG},"Pass")&" of "&ROWS({CK_RNG})&" integrity checks pass"&IF(model_warnings=0,"; no business warnings.","; "&model_warnings&IF(model_warnings=1," business warning"," business warnings")&" below.")'))
write_cell(ss, ck, 4, 2, "Sample data · every integrity row feeds the badge on Summary; the warnings below depend on the inputs and do not")
write_cell(ss, ck, 4, 6, 0.01)                                                     # check_tol, a fixed constant
write_cell(ss, ck, 4, 7, glue('=IF(COUNTIF({CK_RNG},"Fail")=0,"✓ All "&ROWS({CK_RNG})&" checks pass","✕ "&COUNTIF({CK_RNG},"Fail")&" of "&ROWS({CK_RNG})&" checks fail")'))
for (j in 1:6) write_cell(ss, ck, 6, 1L + j, c("#", "Check", "Model value", "Expected", "Difference", "Status")[j])
write_cell(ss, ck, W_BAR, 2, "Business warnings")
write_cell(ss, ck, W_BAR, 7, glue('=COUNTIF(G{W_FIRST}:G{W_LAST},"Warn")'))       # model_warnings
ck_row <- function(rw, i, cx, bad) {
  write_cell(ss, ck, rw, 2, i); write_cell(ss, ck, rw, 3, cx[[1]]); write_cell(ss, ck, rw, 4, cx[[2]]); write_cell(ss, ck, rw, 5, cx[[3]])
  write_cell(ss, ck, rw, 6, if (cx[[4]] == "eq") glue('=IF((D{rw}="")<>(E{rw}=""),1,ROUND(D{rw}-E{rw},4))')   # blank vs number is a difference, blank = blank ties
                            else glue("=MIN(0,ROUND(D{rw}-E{rw},4))"))
  write_cell(ss, ck, rw, 7, glue('=IFERROR(IF(ABS(F{rw})<=check_tol,"Pass","{bad}"),"{bad}")'))
}
for (i in seq_along(CHECKS)) ck_row(CK_FIRST + i - 1L, i, CHECKS[[i]], "Fail")
for (i in seq_along(WARNS))  ck_row(W_FIRST + i - 1L, i, WARNS[[i]], "Warn")

## ---- Summary ----------------------------------------------------------------
sm <- TAB[["sum"]]
ARR24 <- glue("Forecast!{M24}{r$arr}"); CASH24 <- glue("Forecast!{M24}{r$cash_close}")
EBQ <- glue("AVERAGE(Forecast!{mcol(22L)}{r$ebitda}:{M24}{r$ebitda})")     # average EBITDA of the last 3 months
BE_F <- glue("MATCH(TRUE,ARRAYFORMULA(Forecast!D{r$ebitda}:{M24}{r$ebitda}>0),0)")
write_cell(ss, sm, 2, 2, '="SaaS financial model, "&scenario&" scenario"')
write_cell(ss, sm, 2, CTRL$scn[2] - 1L, "Scenario"); write_cell(ss, sm, CTRL$scn[1], CTRL$scn[2], "Base")
# the finding: one live sentence that the lead figure (ARR) answers
write_cell(ss, sm, 3, 2, glue('="ARR reaches "&TEXT({ARR24},"$0.0,,""M""")&" by month 24 ("&TEXT({ARR24}/Forecast!{M12}{r$arr}-1,"+0%;-0%")&" vs month 12); "&IFERROR("EBITDA turns positive in month "&{BE_F},"EBITDA stays negative")&"; "&IF({CASH24}<=0,"cash runs out.","cash ends at "&TEXT({CASH24},"$0.0,,""M""")&".")'))
write_cell(ss, sm, 4, 2, sprintf('="Sample data · 24 months from "&TEXT(first_month,"mmmm yyyy")&" · USD · built %s · View only? File > Make a copy to change the scenario"', Sys.Date()))
write_cell(ss, sm, 4, 9, '=IF(model_warnings=0,"",model_warnings&IF(model_warnings=1," warning"," warnings"))')
write_cell(ss, sm, 4, 10, "=model_status")
KPI <- list(   # label, value, value format, change, change format, good direction
  list("ARR at month 24", glue("={ARR24}"), NF_M1,
       glue('=IFERROR({ARR24}/Forecast!{M12}{r$arr}-1,"-")'), NUMFMT_DELTA_PCT, "up"),
  list("MRR growth/mo, Y2", glue("=Forecast!AD{r$m_growth}"), NF_PCT1,
       glue('=IFERROR((Forecast!AD{r$m_growth}-Forecast!AC{r$m_growth})*100,"-")'), NUMFMT_DELTA_PT, "up"),
  list("NRR, Y2", glue("={XU}!D{U$nrr}"), NF_PCT0,
       glue('=IFERROR(({XU}!D{U$nrr}-{XU}!C{U$nrr})*100,"-")'), NUMFMT_DELTA_PT, "up"),
  list("Gross margin, M24", glue("=Forecast!{M24}{r$gm_pct}"), NF_PCT1,
       glue('=IFERROR((Forecast!{M24}{r$gm_pct}-Forecast!{M12}{r$gm_pct})*100,"-")'), NUMFMT_DELTA_PT, "up"),
  list("LTV : CAC, M24", glue('=IF({XU}!D{U$ltvcac}="","n/a",{XU}!D{U$ltvcac})'), NF_X,          # "n/a" when churn is 0 (LTV undefined)
       glue('="payback "&TEXT({XU}!D{U$payback},"0")&" mo"'), NULL, "none"),
  list("Cash runway, M24",
       glue('=IF({CASH24}<=0,"Cash out",IF({EBQ}>=0,"Self-funded",IF({CASH24}/-{EBQ}>runway_cap,runway_cap&"+ mo",ROUND({CASH24}/-{EBQ},0))))'),
       NF_MO, glue('=TEXT({CASH24},"$0.0,,""M""")&" cash at month 24"'), NULL, "none"))
for (i in seq_along(KPI)) for (j in 0:2) write_cell(ss, sm, SU$kpi + j, K_COLS[i], KPI[[i]][[c(1, 2, 4)[j + 1L]]])
write_cell(ss, sm, SU$kpi + 3L, 2, "M24 = month 24, Y2 = year 2. MRR growth is the average monthly rate. Changes are vs month 12 (ARR, gross margin) or year 1 (growth, NRR): green is better, red is worse.")
# Scenario comparison (left) beside the ARR chart (right): all three scenarios from the Scenarios tab
write_cell(ss, sm, SU$cmp, 2, "Scenario comparison"); write_cell(ss, sm, SU$cmp, 7, "ARR by scenario")
for (j in 1:4) write_cell(ss, sm, SU$cmp + 1L, 1L + j, c("Metric", SCN)[j])
CMP <- list(
  list("ARR, month 24",         function(s) glue("=Scenarios!{M24}{se_row(s, 'arr')}"), NF_M1),
  list("ARR growth, year 2",    function(s) glue('=IFERROR(Scenarios!{M24}{se_row(s, "arr")}/Scenarios!{M12}{se_row(s, "arr")}-1,"")'), NF_DPCT0),
  list("Customers, month 24",   function(s) glue("=Scenarios!{M24}{se_row(s, 'cust')}"), NF_INT),
  list("EBITDA, year 2",        function(s) glue("=SUM(Scenarios!{mcol(13L)}{se_row(s, 'ebitda')}:{M24}{se_row(s, 'ebitda')})"), NF_K),
  list("EBITDA positive from",  function(s) glue('=IFERROR(MATCH(TRUE,ARRAYFORMULA(Scenarios!D{se_row(s, "ebitda")}:{M24}{se_row(s, "ebitda")}>0),0),"After month 24")'), NF('"Month "0')),
  list("Cash, month 24",        function(s) glue("=Scenarios!{M24}{se_row(s, 'cash')}"), NF_M1),
  list("LTV : CAC, month 24",   function(s) glue("=Scenarios!{M24}{se_row(s, 'ltvcac')}"), NF_X))
for (i in seq_along(CMP)) {
  rw <- SU$cmp_first + i - 1L
  write_cell(ss, sm, rw, 2, CMP[[i]][[1]])
  for (s in 1:3) write_cell(ss, sm, rw, 2L + s, CMP[[i]][[2]](s))
}
write_cell(ss, sm, SU$cmp_note, 2, "From the Scenarios tab; the picked scenario is shaded. Checks proves it matches the Forecast.")
# MRR bridge (left, with its period picker) beside the annual snapshot (right)
write_cell(ss, sm, SU$br, 2, '="MRR bridge, "&LOWER(bridge_period)')
write_cell(ss, sm, SU$br, CTRL$per[2] - 1L, "Period"); write_cell(ss, sm, CTRL$per[1], CTRL$per[2], "Year 1")
write_cell(ss, sm, SU$br, 7, "Year 1 and year 2")
for (j in 1:4) write_cell(ss, sm, SU$br + 1L, 6L + j, c("Metric", "Year 1", "Year 2", "Change")[j])
SNAP <- list(list("Revenue", "rev", NF_K), list("Gross profit", "gp", NF_K), list("Operating costs", "opex", NF_K),
             list("EBITDA", "ebitda", NF_K), list("ARR", "arr", NF_K),
             list("Customers", "c_close", NF_INT), list("Cash", "cash_close", NF_K))
for (i in seq_along(SNAP)) {
  rw <- SU$snap_first + i - 1L; sp <- SNAP[[i]]
  write_cell(ss, sm, rw, 7, sp[[1]])
  write_cell(ss, sm, rw, 8, glue("=Forecast!AC{r[[sp[[2]]]]}")); write_cell(ss, sm, rw, 9, glue("=Forecast!AD{r[[sp[[2]]]]}"))
  write_cell(ss, sm, rw, 10, glue('=IF(H{rw}<=0,"n/m",I{rw}/H{rw}-1)'))
}
write_cell(ss, sm, SU$br_note, 2, "The period picker changes the waterfall only. Losses are drawn before gains.")
write_cell(ss, sm, SU$br_note, 7, "Year 1 = months 1-12, year 2 = 13-24. ARR, customers and cash at year end.")
write_cell(ss, sm, SU$mv, 2, "Monthly MRR movements")
write_cell(ss, sm, SU$mv_note, 2, '="Month 1 = "&TEXT(first_month,"mmmm yyyy")&". Contraction and churn are negative. The scenario picker drives this chart."')
write_cell(ss, sm, SU$howto, 2, "How to use this sample")
HOWTO <- c("1  Pick a scenario at the top right: every tab, KPI and chart updates.",
           "2  Pick a bridge period above the waterfall: it changes the waterfall only.",
           "3  Blue cells on Assumptions, Cohorts and Unit Economics are the inputs.",
           "4  The Checks tab proves the model ties (the badge at the top right).",
           "5  To edit anything: File > Make a copy.")
for (i in seq_along(HOWTO)) write_cell(ss, sm, SU$howto + i, 2, HOWTO[i])
write_cell(ss, sm, SU$about, 2, "About this sample")
write_cell(ss, sm, SU$about + 1L, 2, "Sample data only. Every figure is synthetic and generated by a seeded script; no real company, customer, person or amount. Illustrative, not advice.")
write_cell(ss, sm, SU$about + 2L, 2, "Built with the r-googlesheets4 skill (open source, MIT licence):")
write_cell(ss, sm, SU$about + 4L, 2, "Built on googlesheets4 (Jennifer Bryan), gargle (Jennifer Bryan, Craig Citro, Hadley Wickham) and googledrive (Lucy D'Agostino McGowan, Jennifer Bryan); all Posit Software, PBC:")
write_cell(ss, sm, SU$about + 6L, 2, "Unofficial add-on, not affiliated with or endorsed by Posit or Google. Rebuild script: examples/showcases/saas-model.R")

# Theme (font, chart series) and the named ranges go in before the one flush, so every formula resolves on the first pass.
nr_req <- c(list(do.call(fmt_theme_colors, THEME_DEFAULT)),
  lapply(DRV$name, function(n) fmt_named_range(sid[["asm"]], n, A_ROWS[[n]], A_ROWS[[n]], 3L, 3L)),
  list(fmt_named_range(sid[["asm"]], "first_month",  A_FIRST, A_FIRST, 3L, 3L),
       fmt_named_range(sid[["sum"]], "scenario",      CTRL$scn[1], CTRL$scn[1], CTRL$scn[2], CTRL$scn[2]),
       fmt_named_range(sid[["sum"]], "bridge_period", CTRL$per[1], CTRL$per[1], CTRL$per[2], CTRL$per[2]),
       fmt_named_range(sid[["ck"]],  "model_status",  4L, 4L, 7L, 7L),
       fmt_named_range(sid[["ck"]],  "check_tol",     4L, 4L, 6L, 6L),
       fmt_named_range(sid[["ck"]],  "model_warnings", W_BAR, W_BAR, 7L, 7L)))
batch_format(ss, nr_req, strict = TRUE)
flush_writes(ss, strict = TRUE)
Sys.sleep(3)    # let the backend commit values before formatting

# =============================================================================
# 2. FORMATTING, one batch per tab (strict: a failing request names its tab)
# =============================================================================
## ---- Assumptions ------------------------------------------------------------
S <- sid[["asm"]]; n <- GRID$asm
DRV_SIGNED <- c("new_cust_growth", "churn_improve", "gm_gain_per_year", "opex_growth")   # rates that may legitimately be negative
pad <- function(p, type = "NUMBER") NF(sprintf("%s_)_);(%s)_)", p, p), type)   # trailing pad keeps numbers off the Unit text
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "model", widths = c(240, 96, 96, 96, 96, 128, 400), inputs = TRUE, freeze_rows = A_HDR))
b$push(key_fmt(S, 4, 4))
b$push(col_header(S, A_HDR, 2, 8, num = 3:6, ink = TRUE))
b$push(fmt_section(S, A_BAND, 2, 8, header = FALSE))
b$push(fmt_table_body(S, A_SCN, A_FIRST, 2, 8, numeric_cols = 3))
b$push(fmt_cells(S, A_SCN, A_SCN, 3, 3, font_color = COL_LINK_FG))                  # =scenario, from Summary
b$push(apply_style(S, A_FIRST, A_FIRST, 3, 3, STYLE_INPUT, numfmt = NF("mmm yyyy", "DATE")))
for (g in unique(DRV$group)) {
  rows <- unlist(A_ROWS[DRV$name[DRV$group == g]])
  b$push(fmt_section(S, A_ROWS[[paste0("grp_", g)]], 2, 8, header = FALSE))
  b$push(fmt_table_body(S, min(rows), max(rows), 2, 8, numeric_cols = 3:6))
}
for (i in seq_len(nrow(DRV))) {
  rw <- A_ROWS[[DRV$name[i]]]
  nf <- switch(DRV$nf[i], int = pad("#,##0"), usd = pad("$#,##0"), pct = pad("0.0%", "PERCENT"), mo = NF('0" mo"_)_)'))
  dv <- if (DRV$nf[i] != "pct") list("NUMBER_GREATER_THAN_EQ", 0, "Enter a number, 0 or more.")   # counts, dollars, months
        else if (DRV$name[i] %in% DRV_SIGNED) list("NUMBER_BETWEEN", c(-1, 1), "Enter a percentage from -100% to 100%.")
        else list("NUMBER_BETWEEN", c(0, 1), "Enter a percentage from 0% to 100%.")
  b$push(fmt_cells(S, rw, rw, 3, 6, numfmt = nf))
  b$push(apply_style(S, rw, rw, 4, 6, STYLE_INPUT))
  b$push(fmt_validation(S, rw, rw, 4, 6, dv[[1]], dv[[2]], input_message = dv[[3]]))
}
b$push(apply_style(S, A_SCN, A_LAST, 7, 8, STYLE_NOTE))
# the active scenario's header: raised grey and bold (green means a link); CF cannot read a name on another tab, so it reads C7
b$cf(fmt_cond_formula, S, A_HDR, A_HDR, 4, 6, glue("=D${A_HDR}=$C${A_SCN}"), bg_color = COL_RAISED, bold = TRUE)
b$push(fmt_validation(S, A_FIRST, A_FIRST, 3, 3, "DATE_IS_VALID", input_message = "Enter a date, for example 2027-01-01."))
b$push(fmt_protected_range(S, description = "Formulas: edit only the blue input cells",
                           unprotected_ranges = list(grid_range(S, A_FIRST, A_FIRST, 3, 3), grid_range(S, A_FIRST + 1L, A_LAST, 4, 6))))
batch_format(ss, b$get(), strict = TRUE)

## ---- Forecast ---------------------------------------------------------------
S <- sid[["fc"]]; n <- GRID$fc; LASTC <- COL_Y2; MON <- c(4L, 3L + N_M)            # D..AA = the months
SECS <- list(s_drv = c("churn", "gm"), s_cust = c("c_open", "c_close"), s_mrr = c("m_open", "ret_gross"),
             s_pl = c("rev", "ebitda_pct"), s_cash = c("cash_open", "cash_close"), s_ue = c("arpa", "ltv_cac"),
             s_feed = c("f_month", "f_churn"))
LINK_KEYS <- c("churn", "gm", "c_new", "m_new", "m_exp", "m_con", "sm", "rd", "ga", "ltv_cac")   # month cells that read Assumptions
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "model", widths = c(240, 88, rep(72, N_M), 16, 96, 96), freeze_rows = r$hdr, freeze_cols = 3))
b$push(key_fmt(S, r$meta, 8))
b$push(mnum_row(S, MN, LASTC))
b$push(col_header(S, r$hdr, 2, LASTC, num = 3:LASTC))
for (s in names(SECS)) {
  a <- r[[SECS[[s]][1]]]; z <- r[[SECS[[s]][2]]]; in_s <- function(k) intersect(unlist(r[k]), a:z)
  b$push(fmt_section(S, r[[s]], 2, LASTC, header = FALSE))
  b$push(fmt_table_body(S, a, z, 2, LASTC, numeric_cols = 3:LASTC, subtotal_rows = in_s(c("gp", "opex")),
                        total_rows = in_s(c("c_close", "m_close", "ebitda", "cash_close")),
                        total_col = if (s != "s_feed") c(COL_Y1, COL_Y2)))
}
rowfmt <- function(keys, nf) for (k in keys) b$push(fmt_cells(S, r[[k]], r[[k]], 3, LASTC, numfmt = nf))
rowfmt(c("arr", "rev", "cogs", "gp", "sm", "rd", "ga", "opex", "ebitda", "cash_open", "cash_flow", "cash_close"), NF_K)
rowfmt(c("m_open", "m_new", "m_exp", "m_con", "m_churn", "m_close"), NF_K1)
rowfmt(c("c_open", "c_new", "c_churn", "c_close"), NF_INT)
rowfmt("churn", NF_PCT2); rowfmt(c("gm", "m_growth", "ret_net", "ret_gross", "gm_pct", "ebitda_pct"), NF_PCT1)
rowfmt(c("arpa", "ltv"), NF_USD); rowfmt("ltv_cac", NF_X)
# all four movement rows MUST share one number format: the chart's left axis takes its format from them
rowfmt(c("f_new", "f_exp", "f_con", "f_churn"), NF_AXIS_K)
b$push(fmt_cells(S, r$f_month, r$f_churn, 2, LASTC, font_color = COL_TEXT_3))       # chart feed: muted
b$push(fmt_cells(S, r$f_month, r$f_churn, 3, 3, halign = "LEFT"))
for (k in LINK_KEYS) b$push(fmt_cells(S, r[[k]], r[[k]], MON[1], MON[2], font_color = COL_LINK_FG))
for (k in c("c_close", "m_close", "cash_close")) b$push(fmt_cells(S, r[[k]], r[[k]], 3, 3, font_color = COL_LINK_FG))   # opening balances
b$push(apply_style(S, r$note, r$note, 2, 2, STYLE_NOTE))
b$push(fmt_protected_range(S, description = "Forecast is formula-driven; change inputs on Assumptions"))
batch_format(ss, b$get(), strict = TRUE)

## ---- MRR Bridge -------------------------------------------------------------
S <- sid[["br"]]; n <- GRID$br
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "model", widths = c(240, 96, 96, 96, 24, 120, 24, rep(112, 5)), freeze_rows = B$hdr))
b$push(key_fmt(S, B$leg, 9))
b$push(col_header(S, B$hdr, 2, 7, num = c(3:5, 7), ink = TRUE))
b$push(fmt_table_body(S, B$from, B$diff, 2, 7, numeric_cols = c(3:5, 7), total_rows = B$close))
b$push(fmt_cells(S, B$from, B$to, 3, 7, numfmt = NF("0")))
b$push(fmt_cells(S, B$open, B$net, 3, 7, numfmt = NF_USD))
b$push(fmt_cells(S, B$netpct, B$netpct, 3, 7, numfmt = NF_PCT1))
b$push(fmt_cells(S, B$tie, B$diff, 3, 7, numfmt = NF_USD))
for (k in c("from", "to", "diff")) b$push(fmt_cells(S, B[[k]], B[[k]], 2, 7, font_color = COL_TEXT_3))   # fixed period ends, the tie-out difference
for (k in c("open", "new", "exp", "con", "churn", "tie")) b$push(fmt_cells(S, B[[k]], B[[k]], 3, 5, font_color = COL_LINK_FG))
b$push(fmt_cells(S, B$hdr, B$diff, 7, 7, bg_color = COL_RAISED, bold = TRUE))      # the selected period
b$push(apply_style(S, B$note, B$note, 2, 2, STYLE_NOTE))
b$push(fmt_section(S, B$feed_hdr, 2, 7, header = FALSE))
b$push(fmt_table_body(S, B$feed, B$feed + 5L, 2, 3, numeric_cols = 3, numfmt = NF_USD0))   # the chart axis takes this format: zero reads $0, not "-"
b$push(fmt_cells(S, B$feed, B$feed + 5L, 2, 3, font_color = COL_TEXT_3))
b$push(fmt_protected_range(S, description = "Formulas: choose the scenario and period on Summary"))
batch_format(ss, b$get(), strict = TRUE)

## ---- Cohorts ----------------------------------------------------------------
S <- sid[["co"]]; n <- GRID$co; c_last <- CO$avg - 1L
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "model", widths = c(40, 128, 112, 104, rep(60, 12))))   # no freeze: the table fits one screen, and frozen rows would print over the chart on page 2
b$push(key_fmt(S, 4, 14))
b$push(apply_style(S, 5, 5, 2, 17, STYLE_HEADER, font_size = 10, font_color = COL_INK, wrap = FALSE))   # group label over the months
b$push(fmt_borders(S, 5, 5, 2, 17, top = BORDER_INK)); b$push(fmt_row_height(S, 5, 5, 24))
b$push(col_header(S, CO$hdr, 2, 17, num = 4:17)); b$push(fmt_cells(S, CO$hdr, CO$hdr, 6, 17, numfmt = NF('"M"0')))
b$push(fmt_table_body(S, CO$first, CO$avg, 2, 17, numeric_cols = 4:17, total_rows = CO$avg,
                      numfmt = c(list(NF("#,##0.0"), NF("0.00")), rep(list(NF_PCT0), 12))))   # 1 decimal so the column visibly sums
b$push(apply_style(S, CO$first, c_last, 2, 2, STYLE_NOTE, halign = "CENTER"))
b$push(fmt_cells(S, CO$first, c_last, 3, 4, font_color = COL_LINK_FG))              # month and size, from the Forecast
b$push(apply_style(S, CO$first, c_last, 5, 5, STYLE_INPUT))
b$push(apply_style(S, CO$avg + 2L, CO$avg + 4L, 2, 2, STYLE_NOTE))
b$push(fmt_section(S, CO$feed, 2, 17, header = FALSE))
b$push(fmt_table_body(S, CO$feed + 1L, CO$feed + 4L, 5, 17, numeric_cols = 6:17,
                      numfmt = rep(list(NF_PCT0), 12)))
b$push(fmt_cells(S, CO$feed + 1L, CO$feed + 1L, 6, 17, numfmt = NF('"M"0')))
b$push(fmt_cells(S, CO$feed + 1L, CO$feed + 4L, 5, 17, font_color = COL_TEXT_3))
# Retention: colour only where customers are lost (white = still active, amber to red = lost). M0 is always 100%,
# so the scale spans M1..M11 and the cohorts visibly differ; the average row shares it. Text stays ink.
b$cf(fmt_cond_color_scale, S, CO$first, CO$avg, 7, 17, min_color = SCALE_HEAT$max_color,
     mid_color = SCALE_HEAT$mid_color, max_color = SCALE_HEAT$min_color)
b$push(fmt_validation(S, CO$first, c_last, 5, 5, "NUMBER_BETWEEN", c(0.05, 3), input_message = "Quality factor from 0.05 to 3 (higher = lower churn)."))
b$push(fmt_protected_range(S, description = "Heatmap is formula-driven; edit only the blue quality factors",
                           unprotected_ranges = grid_range(S, CO$first, c_last, 5, 5)))
batch_format(ss, b$get(), strict = TRUE)

## ---- Unit Economics ---------------------------------------------------------
S <- sid[["ue"]]; n <- GRID$ue
ue_nf <- list(new = NF_INT, cac = NF_USD, arpa = NF_USD, gm = NF_PCT1, churn = NF_PCT2, life = NF("0.0;(0.0)"),
              ltv = NF_USD, ltvcac = NF_X, payback = NF("0.0;(0.0)"), nrr = NF_PCT1, grr = NF_PCT1,
              growth = NF_PCT1, margin = NF_PCT1, r40 = NF_PCT1, magic = NF("0.00;(0.00)"))
UE_LINK <- c("new", "cac", "arpa", "gm", "churn", "nrr", "grr", "growth", "margin", "magic")   # read the Forecast
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "model", widths = c(240, 96, 96, 24, 112, 120, 400), freeze_rows = U$hdr))
b$push(key_fmt(S, U$leg, 6))
b$push(col_header(S, U$hdr, 2, 8, num = c(3, 4, 6), ink = TRUE)); b$push(fmt_cells(S, U$hdr, U$hdr, 7, 7, halign = "CENTER"))
for (g in list(c("s_acq", "new", "gm"), c("s_ltv", "churn", "payback"), c("s_ret", "nrr", "magic"))) {
  b$push(fmt_section(S, U[[g[1]]], 2, 8, header = FALSE))
  b$push(fmt_table_body(S, U[[g[2]]], U[[g[3]]], 2, 8, numeric_cols = c(3, 4, 6)))
}
for (k in names(ue_nf)) b$push(fmt_cells(S, U[[k]], U[[k]], 3, 4, numfmt = ue_nf[[k]]))
for (k in UE_LINK) b$push(fmt_cells(S, U[[k]], U[[k]], 3, 4, font_color = COL_LINK_FG))
# rules of thumb are inputs shown as text ("< 2%"); Status tests year 2 against them, and only "Watch" is coloured
for (k in names(U_RULE)) b$push(apply_style(S, U[[k]], U[[k]], 6, 6, STYLE_INPUT, numfmt = NF(U_RULE[[k]][[3]])))
b$push(fmt_status(S, U$new, U$magic, 7, 7, c(Watch = "warning")))
b$push(apply_style(S, U$new, U$magic, 8, 8, STYLE_NOTE))
b$push(apply_style(S, U$note, U$note, 2, 2, STYLE_NOTE))
for (k in names(U_RULE)) {                             # thresholds: shares stay 0-100%, the rest just must not be negative
  lo <- if (k == "r40") -1 else 0
  b$push(if (k %in% c("churn", "grr"))
    fmt_validation(S, U[[k]], U[[k]], 6, 6, "NUMBER_BETWEEN", c(0, 1), input_message = "Enter a percentage from 0% to 100%.")
  else
    fmt_validation(S, U[[k]], U[[k]], 6, 6, "NUMBER_GREATER_THAN_EQ", lo, input_message = paste0("Enter a number, ", lo, " or more.")))
}
b$push(fmt_protected_range(S, description = "Formulas: only the blue rule-of-thumb cells are inputs",
                           unprotected_ranges = lapply(names(U_RULE), function(k) grid_range(S, U[[k]], U[[k]], 6, 6))))
batch_format(ss, b$get(), strict = TRUE)

## ---- Scenarios --------------------------------------------------------------
S <- sid[["sn"]]; n <- GRID$sn; LASTC <- 3L + N_M
SE_NF <- list(churn = NF_PCT2, new = NF("#,##0.0"), cust = NF_INT, mrr = NF_K, arr = NF_M1, rev = NF_K,
              gm = NF_PCT1, ebitda = NF_K, cash = NF_K, ltvcac = NF_X)
SN_LINK <- c("churn", "new", "mrr", "gm", "ebitda", "ltvcac")                         # month cells that read Assumptions
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "model", widths = c(240, 88, rep(72, N_M)), freeze_rows = SE$hdr, freeze_cols = 3))
b$push(key_fmt(S, 4, 8))
b$push(mnum_row(S, SE$mnum, LASTC))
b$push(col_header(S, SE$hdr, 2, LASTC, num = 3:LASTC))
for (s in 1:3) {
  b$push(fmt_section(S, se_row(s, "churn") - 1L, 2, LASTC, header = FALSE))
  b$push(fmt_table_body(S, se_row(s, "churn"), se_row(s, "ltvcac"), 2, LASTC, numeric_cols = 3:LASTC))
  for (k in SE_K) b$push(fmt_cells(S, se_row(s, k), se_row(s, k), 3, LASTC, numfmt = SE_NF[[k]]))
  for (k in SN_LINK) b$push(fmt_cells(S, se_row(s, k), se_row(s, k), 4, LASTC, font_color = COL_LINK_FG))
  for (k in c("cust", "mrr", "cash")) b$push(fmt_cells(S, se_row(s, k), se_row(s, k), 3, 3, font_color = COL_LINK_FG))
}
b$push(fmt_section(S, SE$feed, 2, LASTC, header = FALSE))
b$push(fmt_table_body(S, SE_F$date, SE_F$mark, 2, LASTC, numeric_cols = 3:LASTC))
b$push(fmt_cells(S, SE_F$date, SE_F$mark, 2, LASTC, font_color = COL_TEXT_3))
b$push(fmt_cells(S, SE_F$date, SE_F$mark, 3, 3, halign = "LEFT"))
b$push(fmt_cells(S, SE_F$date, SE_F$date, 4, LASTC, numfmt = NF("mmm yy", "DATE")))
b$push(fmt_cells(S, SE_F$base, SE_F$mark, 4, LASTC, numfmt = NF_AXIS_M))
b$push(apply_style(S, SE$note, SE$note, 2, 2, STYLE_NOTE))
b$push(fmt_protected_range(S, description = "Formulas: nothing to edit on this tab"))
batch_format(ss, b$get(), strict = TRUE)

## ---- Checks -----------------------------------------------------------------
S <- sid[["ck"]]; n <- GRID$ck
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "dashboard", widths = c(40, 420, 136, 136, 136, 152)))
b$push(apply_style(S, 4, 4, 6, 6, STYLE_NOTE, halign = "RIGHT", numfmt = NF('"Tolerance "0.00')))   # a fixed constant, not an input
b$push(fmt_status(S, 4, 4, 7, 7, c("✓" = "positive", "✕" = "negative"), op = "starts_with"))       # the model badge
b$push(fmt_row_height(S, 5, 5, 12))
b$push(col_header(S, 6, 2, 7, num = 4:6, ink = TRUE)); b$push(fmt_cells(S, 6, 6, 7, 7, halign = "CENTER"))
for (blk in list(c(CK_FIRST, CK_LAST), c(W_FIRST, W_LAST))) {
  b$push(fmt_table_body(S, blk[1], blk[2], 2, 7, numeric_cols = 4:6, numfmt = NF_CHK))
  b$push(apply_style(S, blk[1], blk[2], 2, 2, STYLE_NOTE, halign = "CENTER"))
  b$push(fmt_status(S, blk[1], blk[2], 7, 7, c(Fail = "negative", Warn = "warning")))   # Pass stays plain grey
}
b$push(fmt_row_height(S, CK_LAST + 1L, CK_LAST + 1L, 20))
b$push(fmt_section(S, W_BAR, 2, 7, header = FALSE, meta_col = 7)); b$push(fmt_cells(S, W_BAR, W_BAR, 7, 7, numfmt = NF('0" flagged"')))
b$push(fmt_protected_range(S, description = "Formulas only: nothing to edit on this tab"))
batch_format(ss, b$get(), strict = TRUE)

## ---- Summary ----------------------------------------------------------------
S <- sid[["sum"]]; n <- GRID$sum
RUNWAY_LOW <- sprintf('=OR(%s="Cash out",AND(ISNUMBER(%s),%s<INDIRECT("Assumptions!$C$%d")))',
                      kpi_cell(6), kpi_cell(6), kpi_cell(6), A_ROWS[["runway_warn"]])
cmp_last <- SU$cmp_first + length(CMP) - 1L; snap_last <- SU$snap_first + length(SNAP) - 1L
b <- new_batch()
b$push(fmt_tab_base(S, n[1], n[2], "dashboard", widths = c(224, 112, 112, 112, 24, 120, 120, 120, 152)))
b$push(control(S, CTRL$scn[1], CTRL$scn[2]))
b$push(fmt_status(S, 4, 4, 9, 9, c(warning = "warning"), op = "contains"))                 # business warnings, when there are any
b$push(fmt_status(S, 4, 4, 10, 10, c("✓" = "positive", "✕" = "negative"), op = "starts_with"))   # the model badge
b$push(fmt_kpi_strip(S, SU$kpi, K_COLS, lead = 2, good = vapply(KPI, `[[`, "", 6), rule_end_col = 10,
                     value_numfmt = lapply(KPI, `[[`, 3), delta_numfmt = lapply(KPI, function(k) k[[5]]),
                     tol = c(0.0005, 0.05, 0.05, 0.05, 0, 0)))   # half the last shown digit: "+0.0 pts" stays grey
b$push(apply_style(S, SU$kpi + 3L, SU$kpi + 3L, 2, 2, STYLE_NOTE))
for (rw in c(SU$cmp, SU$br)) for (blk in list(c(2, 5), c(7, 10))) b$push(fmt_section(S, rw, blk[1], blk[2], header = FALSE))
for (rw in c(SU$mv, SU$howto, SU$about)) b$push(fmt_section(S, rw, 2, 10, header = FALSE))
b$push(control(S, CTRL$per[1], CTRL$per[2]))
b$push(col_header(S, SU$cmp + 1L, 2, 5, num = 3:5)); b$push(col_header(S, SU$br + 1L, 7, 10, num = 8:10))
b$push(fmt_table_body(S, SU$cmp_first, cmp_last, 2, 5, numeric_cols = 3:5, density = "dashboard"))
for (i in seq_along(CMP)) b$push(fmt_cells(S, SU$cmp_first + i - 1L, SU$cmp_first + i - 1L, 3, 5, numfmt = CMP[[i]][[3]]))
b$push(fmt_table_body(S, SU$snap_first, snap_last, 7, 10, numeric_cols = 8:10, density = "dashboard"))
for (i in seq_along(SNAP)) b$push(fmt_cells(S, SU$snap_first + i - 1L, SU$snap_first + i - 1L, 8, 9, numfmt = SNAP[[i]][[3]]))
b$push(fmt_cells(S, SU$snap_first, snap_last, 10, 10, numfmt = NF_DPCT0, font_color = COL_TEXT_3))
for (rw in c(SU$cmp_note, SU$br_note, SU$mv_note)) b$push(apply_style(S, rw, rw, 2, 7, STYLE_NOTE))
b$push(apply_style(S, SU$howto + 1L, SU$howto + length(HOWTO), 2, 2, STYLE_BODY, font_color = COL_TEXT_2))
b$push(apply_style(S, SU$about + 1L, SU$about + 6L, 2, 2, STYLE_BODY, font_color = COL_TEXT_2))
b$push(fmt_cells(S, SU$about + 3L, SU$about + 3L, 2, 2, font_color = COL_ACCENT_700))   # the two link rows (theme link colour)
b$push(fmt_cells(S, SU$about + 5L, SU$about + 5L, 2, 2, font_color = COL_ACCENT_700))
for (rh in list(c(5, 5, 12), c(9, 10, 20), c(SU$cmp_note - 1L, SU$cmp_note - 1L, 8), c(SU$cmp_note, SU$cmp_note + 1L, 20),
                c(SU$br_note - 1L, SU$br_note - 1L, 8), c(SU$br_note, SU$br_note + 1L, 20),
                c(SU$mv + 1L, SU$mv + 10L, 28), c(SU$mv_note - 1L, SU$mv_note - 1L, 8), c(SU$mv_note, SU$mv_note + 1L, 20),
                c(SU$howto + 1L, SU$howto + length(HOWTO), 22), c(SU$howto + length(HOWTO) + 1L, SU$howto + length(HOWTO) + 1L, 20),
                c(SU$about + 1L, SU$about + 6L, 22), c(SU$about + 7L, SU$about + 7L, 12)))
  b$push(fmt_row_height(S, rh[1], rh[2], rh[3]))
b$push(fmt_dropdown(S, CTRL$scn[1], CTRL$scn[1], CTRL$scn[2], CTRL$scn[2], SCN))
b$push(fmt_dropdown(S, CTRL$per[1], CTRL$per[1], CTRL$per[2], CTRL$per[2], c("Year 1", "Year 2", "Full period")))
b$push(fmt_protected_range(S, description = "Dashboard: formulas. Edit only the two pickers",
                           unprotected_ranges = list(grid_range(S, CTRL$scn[1], CTRL$scn[1], CTRL$scn[2], CTRL$scn[2]),
                                                     grid_range(S, CTRL$per[1], CTRL$per[1], CTRL$per[2], CTRL$per[2]))))
batch_format(ss, b$get(), strict = TRUE)

# Conditional formatting on Summary, its own batch: colour only where there is risk. KPI values turn red when the
# runway is short and amber when NRR or LTV : CAC reads "Watch" on Unit Economics (CF cannot name another tab,
# hence INDIRECT); the picked scenario's column is raised grey and bold. Only the first matching rule applies,
# so a negative in the picked column gets one rule with both looks, listed first.
b <- new_batch()
picked <- sprintf("C$%d=$%s$%d", SU$cmp + 1L, col_letter(CTRL$scn[2]), CTRL$scn[1])
b$cf(fmt_cond_formula, S, SU$cmp + 1L, cmp_last, 3, 5, sprintf("=AND(%s,N(C%d)<0)", picked, SU$cmp + 1L),
     bg_color = COL_RAISED, bold = TRUE, font_color = COL_NEGATIVE)
b$cf(fmt_cond_formula, S, SU$cmp + 1L, cmp_last, 3, 5, paste0("=", picked), bg_color = COL_RAISED, bold = TRUE)
for (kp in list(c(3L, U$nrr), c(5L, U$ltvcac)))
  b$cf(fmt_cond_formula, S, SU$kpi + 1L, SU$kpi + 1L, K_COLS[kp[1]], K_COLS[kp[1]],
       sprintf('=INDIRECT("\'Unit Economics\'!$G$%d")="Watch"', kp[2]), font_color = STATUS$warning$ink)
b$cf(fmt_cond_formula, S, SU$kpi + 1L, SU$kpi + 1L, K_COLS[6], K_COLS[6], RUNWAY_LOW, font_color = COL_NEGATIVE)
b$cf(fmt_cond_negative, S, SU$cmp_first, cmp_last, 3, 5, color = COL_NEGATIVE)
b$cf(fmt_cond_negative, S, SU$snap_first, snap_last, 8, 9, color = COL_NEGATIVE)
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()   # Checks: the warning count turns amber when anything is flagged
b$cf(fmt_cond_number, sid[["ck"]], W_BAR, W_BAR, 7, 7, 0, "greater", bg_color = STATUS$warning$fill,
     font_color = STATUS$warning$ink, bold = TRUE)
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# 3. CHARTS (after values exist; each reads its data tab and sits on Summary, Bridge or Cohorts). One hue per
#    chart: the accent on the main series, greys for comparisons; scenarios are not states, so no status colours.
# =============================================================================
wf <- function(anchor_row, anchor_col, size, on)       # `on` = tab the chart sits on; the data is on MRR Bridge
  fmt_chart_waterfall(sid[["br"]], TTL$wf,               # colours: the token defaults (gains, losses, accent totals)
                      domain_range = c(B$feed, B$feed + 5L, 2, 2), data_range = c(B$feed, B$feed + 5L, 3, 3),
                      subtotal_indices = c(0L, 5L),            # Opening and Closing are totals
                      subtotal_label = "Total", data_labels = TRUE,
                      anchor = c(anchor_row, anchor_col), size = size, anchor_sheet_id = on, style = STYLE_CHART)
fcs <- sid[["fc"]]; sns <- sid[["sn"]]
dom <- c(r$f_month, r$f_month, 3, 3L + N_M)
rowr <- function(k) c(r[[k]], r[[k]], 3, 3L + N_M)
rows_sn <- function(row) c(row, row, 3, 3L + N_M)
# ARR by scenario: the three scenarios in grey (base solid, upside dotted, downside dashed), the selected one again
# on top in the accent, and markers (with value labels) at months 12 and 24
arr_chart <- fmt_chart_basic(sns, TTL$arr, "LINE", rows_sn(SE_F$date),
                             list(list(range = rows_sn(SE_F$base), color = GREY, line = list(width = 2)),
                                  list(range = rows_sn(SE_F$up), color = GREY, line = list(width = 2, type = "DOTTED")),
                                  list(range = rows_sn(SE_F$down), color = GREY, line = list(width = 2, type = "MEDIUM_DASHED")),
                                  list(range = rows_sn(SE_F$sel), color = COL_ACCENT, line = list(width = 3)),
                                  list(range = rows_sn(SE_F$mark), color = COL_ACCENT,
                                       line = list(type = "INVISIBLE", width = 0), point = list(shape = "CIRCLE", size = 7),
                                       label = list(type = "DATA", placement = "BELOW"))),
                             anchor = c(SU$cmp + 1L, 7), size = c(512L, 250L), legend = "TOP_LEGEND", y_title = "ARR",
                             anchor_sheet_id = sid[["sum"]], style = STYLE_CHART)
mv_chart <- fmt_chart_basic(fcs, TTL$mv, "COLUMN", dom,
                            list(list(range = rowr("f_new"), color = COL_ACCENT),
                                 list(range = rowr("f_exp"), color = COL_ACCENT_400),
                                 list(range = rowr("f_con"), color = GREY),
                                 list(range = rowr("f_churn"), color = DARK)),
                            stacked_type = "STACKED", anchor = c(SU$mv + 1L, 2), size = c(1096L, 280L), legend = "TOP_LEGEND",
                            x_title = "Month of the forecast", y_title = "MRR per month", anchor_sheet_id = sid[["sum"]],
                            style = STYLE_CHART)                   # full width: at 464 px the 24 month labels turned vertical
batch_format(ss, list(wf(SU$br + 1L, 2, c(560L, 230L), sid[["sum"]]),   # 560 px = B-E; at 550+ px the bar labels stay flat
                      arr_chart, mv_chart), strict = TRUE)
# Cohort retention curves: feed rows on the Cohorts tab, the chart sits below them.
cr <- function(row) c(row, row, 5, 17)
co_chart <- fmt_chart_basic(sid[["co"]], TTL$co, "LINE", cr(CO$feed + 1L),
                            list(list(range = cr(CO$feed + 2L), color = GREY, line = list(width = 2, type = "DOTTED")),
                                 list(range = cr(CO$feed + 3L), color = COL_ACCENT, line = list(width = 3)),
                                 list(range = cr(CO$feed + 4L), color = DARK, line = list(width = 2, type = "MEDIUM_DASHED"))),
                            anchor = c(CO$chart, 2), size = c(760L, 300L), legend = "TOP_LEGEND",
                            x_title = "Months since signup", y_title = "Customers still active",
                            y_min = 0, y_max = 1,                              # 0-100% fits any quality input (a low one can fall under 50%)
                            style = STYLE_CHART)
# The Bridge waterfall is 560 px wide: at 550+ the category labels stay horizontal (at 520 they slanted and clipped "MRR").
batch_format(ss, list(wf(B$chart, B$chart_col, c(560L, 340L), sid[["br"]]), co_chart), strict = TRUE)

# Rich-text links last: the cells are pre-coloured in the Summary batch, and link_cells_req() keeps that colour.
batch_format(ss, list(
  link_cells_req(sid[["sum"]], SU$about + 3L, 2, REPO_URL, REPO_URL),
  link_cells_req(sid[["sum"]], SU$about + 5L, 2, DOCS_URL, DOCS_URL)), strict = TRUE)

# =============================================================================
# 4. POST-BUILD QA (cells; the visual pass is run separately with visual_qa())
# =============================================================================
Sys.sleep(3)
cnt <- gs_count_objects(ss_id); n_ch <- setNames(cnt$charts, cnt$tab)
stopifnot("chart count per tab (a rerun must not stack charts)" =              # also catches a chart that failed to land
            identical(n_ch[TAB], setNames(c(3L, 0L, 0L, 1L, 1L, 0L, 0L, 0L), TAB)))
props <- googlesheets4::sheet_properties(ss)
stopifnot(props$index[props$name == TAB[["sum"]]] == 0L)               # Summary is the first tab
err_pat <- "^#(REF|DIV/0|NAME|N/A|VALUE|NUM|NULL|ERROR)|^Err:|^###"
n_err <- 0L
for (k in names(TAB)) {
  vals <- read_values(ss, sprintf("'%s'!A1:%s%d", TAB[[k]], col_letter(GRID[[k]][2]), GRID[[k]][1]))[[1]]
  bad <- grep(err_pat, vals, value = TRUE)
  if (length(bad)) { n_err <- n_err + length(bad); message("[QA] error values on ", TAB[[k]], ": ", paste(unique(bad), collapse = ", ")) }
}
stopifnot(n_err == 0L)
status <- read_values(ss, "Checks!G4")[[1]][1, 1]
message("[QA] no error values in any tab; Checks status = ", status)
stopifnot(startsWith(status, "✓"))
# The chart titles were computed in R: the sheet's own Scenarios tab must agree with that simulation.
arr_sheet <- vapply(1:3, function(s) as.numeric(read_values(ss, sprintf("Scenarios!%s%d", M24, se_row(s, "arr")), "UNFORMATTED_VALUE")[[1]][1, 1]), 0)
stopifnot("Scenarios ARR at month 24 differs from the R simulation behind the chart titles" = all(abs(arr_sheet / arr24 - 1) < 1e-9))
stopifnot(length(audit_chart_sources(ss_id)) == 0L)                      # no chart reads a hidden column, on any tab

cat("\nSheet id : ", ss_id, "\nSheet URL: https://docs.google.com/spreadsheets/d/", ss_id,
    "\nRebuild  : SHEET_ID=", ss_id, " GS_SKILL_DIR=", SKILL, " Rscript examples/showcases/saas-model.R\n", sep = "")
