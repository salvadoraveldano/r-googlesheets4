# =============================================================================
# saas-model.R - SaaS financial model showcase (SAMPLE DATA)
#
# Builds   An 8-tab, driver-based, 24-month SaaS model in one Google Sheet:
#          Summary (dashboard: headline sentence, KPI cards with sparklines, MRR
#          waterfall, ARR-by-scenario chart, stacked MRR-movement chart, scenario
#          comparison table), Assumptions (Base / Upside / Downside scenario
#          table), Forecast, MRR Bridge, Cohorts (retention heatmap and curves),
#          Unit Economics, Scenarios (all three scenarios computed side by side,
#          straight from the Assumptions columns) and Checks. One scenario cell
#          on Summary drives the whole model through named ranges.
# Rerun    SHEET_ID=<id> GS_SKILL_DIR=/path/to/skills/r-googlesheets4 \
#              Rscript examples/showcases/saas-model.R
#          (leave SHEET_ID unset to create a new file; the id is printed.
#          Safety: a rerun clears the 8 tabs of that file, so gs_open_or_create() stops before
#          changing anything when SHEET_ID is a file with another title that lacks these tabs.)
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

# -- Theme --------------------------------------------------------------------
FONT       <- BRAND_FONT                          # Arial
COL_INPUT  <- hex_to_color("FFF4B8")              # input cells: yellow fill + brand-blue text
COL_CALC   <- hex_to_color("F1F3F4")              # formula cells: light grey fill
COL_RULE   <- hex_to_color("D9DEE7")              # hairlines
COL_MUTED  <- COL_MUTED_TEXT
COL_SOFT_B <- hex_to_color("8AB4F8")              # second blue for the stacked chart
COL_AMBER_TEXT <- hex_to_color("945A06")
NF <- function(p, type = "NUMBER") list(type = type, pattern = p)   # a custom number format, as fmt_cells(numfmt = ) takes it
NF_K      <- NUMFMT_CURRENCY_K                    # $1,234K
NF_USD    <- NUMFMT_CURRENCY
NF_INT    <- NF('#,##0;(#,##0);"-"')
NF_PCT1   <- NUMFMT_PCT
NF_PCT2   <- NF("0.00%", "PERCENT")
NF_PCT0   <- NUMFMT_PCT_WHOLE
NF_X      <- NF('0.0"x"')
NF_CHK    <- NF("#,##0.00;-#,##0.00;0.00")
NF_AXIS_K <- NF('$#,##0.0,"K";-$#,##0.0,"K";$0')   # one decimal: contraction is a few $K, and the Downside axis steps by 2.5K
NF_ARR_M  <- NF('$#,##0.0,,"M"')
NF_USD0   <- NF('$#,##0;($#,##0);$0')                # waterfall source: the zero tick reads $0, not "-"
NF_CASH_M <- NF('$#,##0.00,,"M";-$#,##0.00,,"M";$0.00"M"')
COL_GREEN_TXT <- hex_to_color("137333")              # status text: 5:1 on white
COL_RED_TXT   <- hex_to_color("B3261E")

# -- Layout (pure data; no API calls) -------------------------------------------
TAB <- c(sum = "Summary", asm = "Assumptions", fc = "Forecast", br = "MRR Bridge",
         co = "Cohorts", ue = "Unit Economics", sn = "Scenarios", ck = "Checks")
XB <- "'MRR Bridge'"; XU <- "'Unit Economics'"

# Forecast: one row per key; months run across (D = month 1 ... AA = month 24).
F_KEYS <- c("title", "sub", "hdr", "mnum",
            "s_drv", "churn", "gm",
            "s_cust", "c_open", "c_new", "c_churn", "c_close",
            "s_mrr", "m_open", "m_new", "m_exp", "m_con", "m_churn", "m_close", "arr",
            "m_growth", "ret_net", "ret_gross",
            "s_pl", "rev", "cogs", "gp", "gm_pct", "sm", "rd", "ga", "opex", "ebitda", "ebitda_pct",
            "s_cash", "cash_open", "cash_flow", "cash_close",
            "s_ue", "arpa", "ltv", "ltv_cac",
            "s_feed", "f_month", "f_new", "f_exp", "f_con", "f_churn")
r <- as.list(setNames(seq_along(F_KEYS), F_KEYS))      # Forecast row numbers
N_M <- 24L
MN <- r$mnum                                           # row that holds the month number
mcol <- function(t) col_letter(3L + t)                 # column letter of month t
COL_Y1 <- 29L; COL_Y2 <- 30L                           # AC, AD: Year 1 / Year 2 totals
M12 <- mcol(12L); M24 <- mcol(24L)                      # O, AA

U <- list(title = 2, sub = 3, leg = 4, hdr = 5, s_acq = 6, new = 7, cac = 8, arpa = 9, gm = 10,
          s_ltv = 11, churn = 12, life = 13, ltv = 14, ltvcac = 15, payback = 16,
          s_ret = 17, nrr = 18, grr = 19, growth = 20, margin = 21, r40 = 22, magic = 23)
# Rules of thumb as numbers (operator, threshold, display format): the Status column tests year 2 against them.
U_RULE <- list(churn = list("<", 0.02, '"< "0%'), ltvcac = list(">=", 3, '">= "0.0"x"'),
               payback = list("<=", 18, '"<= "0" mo"'), nrr = list(">=", 1, '">= "0%'),
               grr = list(">=", 0.8, '">= "0%'), r40 = list(">=", 0.4, '">= "0%'),
               magic = list(">", 0.75, '"> "0.00'))
B <- list(title = 2, sub = 3, leg = 4, hdr = 6, from = 7, to = 8, open = 9, new = 10, exp = 11,
          con = 12, churn = 13, close = 14, net = 15, netpct = 16, tie = 17, diff = 18,
          chart = 7, chart_col = 9,                    # chart sits right of the table, below the frozen rows
          feed_hdr = 21L, feed = 22L)                  # waterfall feed: 6 rows, losses before gains (see below)
CO <- list(first = 7L, n = 12L, avg = 19L, hdr = 6L,   # cohort rows 7..18, average row 19
           feed = 25L, chart = 31L)                    # curve feed rows 26..29, chart below it
# Scenarios: three blocks (Base, Upside, Downside), each a bar plus 10 rows, then the ARR chart feed.
SE <- list(hdr = 5L, mnum = 6L, first = 7L, step = 12L, feed = 43L)
SE_K <- c("churn", "new", "cust", "mrr", "arr", "rev", "gm", "ebitda", "cash", "ltvcac")
se_row <- function(s, k) SE$first + (s - 1L) * SE$step + match(k, SE_K)   # s: 1 Base, 2 Upside, 3 Downside
SE_F <- list(date = 44L, base = 45L, up = 46L, down = 47L, sel = 48L, mark = 49L)
SCN <- c("Base", "Upside", "Downside"); SCN_COL <- c("D", "E", "F")       # scenario names, Assumptions columns
# Summary rows below the movements chart: scenario comparison, then the About block.
SU <- list(cmp = 49L, cmp_hdr = 50L, cmp_first = 51L, cmp_note = 58L, about = 60L)

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
A_HDR <- 5L; A_BAND <- 6L; A_SCN <- 7L; A_FIRST <- 8L  # Assumptions: header, settings band, scenario echo, first-month input
A_ROWS <- list(); a_next <- A_FIRST + 1L               # row of each group header / driver
for (g in unique(DRV$group)) {
  A_ROWS[[paste0("grp_", g)]] <- a_next; a_next <- a_next + 1L
  for (n in DRV$name[DRV$group == g]) { A_ROWS[[n]] <- a_next; a_next <- a_next + 1L }
}
A_LAST <- a_next - 1L

GRID <- list(sum = c(68L, 14L), asm = c(A_LAST + 3L, 9L), fc = c(max(unlist(r)) + 3L, 31L),
             br = c(44L, 14L), co = c(50L, 18L), ue = c(26L, 8L), sn = c(52L, 28L), ck = c(34L, 8L))

# -- Small local helpers --------------------------------------------------------
# Base text style for a whole tab (skill preset STYLE_BODY, plus ink colour), laid down first in each
# tab's batch. Later fmt_cells() calls name only the properties they change; each is masked on its own.
tab_base <- function(sid, n, size = 11)
  apply_style(sid, 1, n[1], 1, n[2], STYLE_BODY,
              font_size = size, bold = FALSE, italic = FALSE, font_color = COL_INK)
ln <- function(sid, r1, r2, c1, c2, where = "bottom", style = "SOLID", color = COL_RULE) {   # one-side border with the hairline colour as default
  args <- list(sid, r1, r2, c1, c2); args[[where]] <- list(style = style, color = color)
  do.call(fmt_borders, args)
}
CHART_STYLE <- list(font = FONT, title_size = 13, title_bold = TRUE, title_color = COL_BRAND_DEEP)   # Arial and a deep-blue title, to match the cells

# -- Connect, create or reuse the sheet, reset it -------------------------------
gs_connect(USER_EMAIL)
# gs_open_or_create() refuses a SHEET_ID that is another file, but does not check the locale (set only at creation).
if (nzchar(Sys.getenv("SHEET_ID", "")))
  stopifnot("SHEET_ID must point at an en_US file (locale is only set when the file is created)" =
              identical(googlesheets4::gs4_get(googlesheets4::as_sheets_id(Sys.getenv("SHEET_ID")))$locale, "en_US"))
ss <- gs_open_or_create(SHEET_TITLE, unname(TAB),
                        time_zone = "Etc/GMT", locale = "en_US",       # create-only: neutral zone for a public file, en_US so TEXT() and dates read as expected
                        rows = setNames(vapply(GRID, `[`, 0, 1L), TAB[names(GRID)]),
                        cols = setNames(vapply(GRID, `[`, 0, 2L), TAB[names(GRID)]))
ss_id <- as.character(ss)
props <- googlesheets4::sheet_properties(ss)
sid   <- setNames(as.numeric(props$id[match(TAB, props$name)]), names(TAB))
batch_format(ss, fmt_tab_order(ss, unname(TAB)), strict = TRUE)         # tab order = the order of TAB
gs_reset_tabs(ss, tabs = unname(TAB))                                   # rebuild in place: charts, names, protections, rules, merges, values, formats

# Named ranges must exist BEFORE any formula that uses them is written (else #NAME?).
nr_req <- lapply(DRV$name, function(n)
  fmt_named_range(sid[["asm"]], n, A_ROWS[[n]], A_ROWS[[n]], 3L, 3L))
nr_req <- c(nr_req, list(
  fmt_named_range(sid[["asm"]], "first_month",  A_FIRST, A_FIRST, 3L, 3L),
  fmt_named_range(sid[["sum"]], "scenario",      5L, 5L, 3L, 3L),
  fmt_named_range(sid[["sum"]], "bridge_period", 5L, 5L, 7L, 7L),
  fmt_named_range(sid[["ck"]],  "model_status",  4L, 4L, 4L, 4L),
  fmt_named_range(sid[["ck"]],  "model_warnings", 5L, 5L, 7L, 7L),
  fmt_named_range(sid[["ck"]],  "check_tol",     4L, 4L, 7L, 7L)))
batch_format(ss, nr_req, strict = TRUE)

# =============================================================================
# 1. VALUES AND FORMULAS (buffered, one flush)
# =============================================================================
## ---- Assumptions ------------------------------------------------------------
write_cell(ss, TAB[["asm"]], 2, 2, "Assumptions")
write_cell(ss, TAB[["asm"]], 3, 2, "Sample data  |  Three scenarios feed the whole model; the Live column follows the scenario chosen on Summary.")
write_cell(ss, TAB[["asm"]], 4, 2, "Legend")
write_cell(ss, TAB[["asm"]], 4, 3, "Input"); write_cell(ss, TAB[["asm"]], 4, 4, "Formula")
for (i in 1:7) write_cell(ss, TAB[["asm"]], A_HDR, 1L + i,
                   c("Driver", "In use", "Base", "Upside", "Downside", "Unit", "Notes")[i])
write_cell(ss, TAB[["asm"]], A_BAND, 2, "Model settings")
write_cell(ss, TAB[["asm"]], A_SCN, 2, "Scenario (change it on Summary)")
write_cell(ss, TAB[["asm"]], A_SCN, 3, "=scenario")
write_cell(ss, TAB[["asm"]], A_FIRST, 2, "First forecast month")
write_cell(ss, TAB[["asm"]], A_FIRST, 3, FIRST_MONTH)
write_cell(ss, TAB[["asm"]], A_FIRST, 7, "date"); write_cell(ss, TAB[["asm"]], A_FIRST, 8, "Month 1 of the 24-month forecast")
for (g in unique(DRV$group)) write_cell(ss, TAB[["asm"]], A_ROWS[[paste0("grp_", g)]], 2, g)
for (i in seq_len(nrow(DRV))) {
  rw <- A_ROWS[[DRV$name[i]]]
  write_cell(ss, TAB[["asm"]], rw, 2, DRV$label[i])
  write_cell(ss, TAB[["asm"]], rw, 3, sprintf("=IFERROR(INDEX(D%d:F%d,MATCH(scenario,$D$%d:$F$%d,0)),D%d)",
                                 rw, rw, A_HDR, A_HDR, rw))
  write_cell(ss, TAB[["asm"]], rw, 4, DRV$base[i]); write_cell(ss, TAB[["asm"]], rw, 5, DRV$up[i]); write_cell(ss, TAB[["asm"]], rw, 6, DRV$down[i])
  write_cell(ss, TAB[["asm"]], rw, 7, DRV$unit[i]); write_cell(ss, TAB[["asm"]], rw, 8, DRV$note[i])
}

## ---- Forecast ---------------------------------------------------------------
fc <- TAB[["fc"]]
write_cell(ss, fc, r$title, 2, "Forecast: 24 months, monthly")
write_cell(ss, fc, r$sub, 2, '="Scenario: "&scenario&"  |  Sample data  |  $ shown in thousands (K)  |  Costs are positive; MRR decreases are negative"')
write_cell(ss, fc, r$hdr, 2, "Line item"); write_cell(ss, fc, r$hdr, 3, "Start"); write_cell(ss, fc, r$hdr, COL_Y1, "Year 1"); write_cell(ss, fc, r$hdr, COL_Y2, "Year 2")
write_cell(ss, fc, r$mnum, 2, "Month number"); write_cell(ss, fc, r$mnum, 3, 0L)
SEC <- c(s_drv = "DRIVERS (live from Assumptions)", s_cust = "CUSTOMERS", s_mrr = "MRR BUILD",
         s_pl = "P&L", s_cash = "CASH", s_ue = "UNIT ECONOMICS BY MONTH",
         s_feed = "CHART FEED (drives the Summary movements chart; do not edit)")
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
         f_month = "Month label", f_new = "New MRR", f_exp = "Expansion MRR",
         f_con = "Contraction MRR", f_churn = "Churned MRR")
for (k in names(LBL)) write_cell(ss, fc, r[[k]], 2, LBL[[k]])
FEED_NAME <- c(f_month = "Month", f_new = "New", f_exp = "Expansion",
               f_con = "Contraction", f_churn = "Churn")
for (k in names(FEED_NAME)) write_cell(ss, fc, r[[k]], 3, FEED_NAME[[k]])      # series names for the charts
write_cell(ss, fc, r$c_close, 3, "=start_customers"); write_cell(ss, fc, r$m_close, 3, "=start_mrr")
write_cell(ss, fc, r$arr, 3, glue("=C{r$m_close}*12")); write_cell(ss, fc, r$cash_close, 3, "=start_cash")
write_cell(ss, fc, r$arpa, 3, glue('=IF(C{r$c_close}=0,"",C{r$m_close}/C{r$c_close})'))

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
    f_month   = glue("={L}${r$hdr}"),
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
write_cell(ss, br, B$title, 2, "MRR Bridge")
write_cell(ss, br, B$sub, 2, '="Sample data  |  Scenario: "&scenario&"  |  Selected period: "&bridge_period')
write_cell(ss, br, B$leg, 2, "Pick the scenario and the bridge period on the Summary tab. Contraction and churn are negative.")
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
# Waterfall feed: opening, losses, gains, closing. A native waterfall has no legend or axis control, so the
# legend sits centred above the plot; with losses first the highest bars are the gains and the closing level,
# which sit to the right of it, and the tall middle bars no longer print their labels over the legend.
WF_ORDER <- c("open", "churn", "con", "exp", "new", "close")
write_cell(ss, br, B$feed_hdr, 2, "CHART FEED (waterfall order: opening, losses, gains, closing; do not edit)")
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
write_cell(ss, co, 2, 2, "Cohort retention")
write_cell(ss, co, 3, 2, '="Sample data  |  Scenario: "&scenario&"  |  Share of each signup cohort still active, by months since signup"')
write_cell(ss, co, 4, 2, "Cohort sizes come from the Forecast. Churn per cohort = scenario churn / quality (yellow, 0.05 to 3; the formulas never use less than 0.05): higher quality, lower churn.")
write_cell(ss, co, 5, 6, "MONTHS SINCE SIGNUP")
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
write_cell(ss, co, CO$avg + 2L, 2, "How to read: each row is the group of customers who signed up in that month. Reading right, the colour shows how many are still active.")
write_cell(ss, co, CO$avg + 3L, 2, "Empty cells are months that have not happened yet inside the 12-month window. Change the scenario on Summary to see the heatmap move.")
q_rng <- glue("$E${CO$first}:$E${CO$avg - 1L}")                                   # live text: it follows the yellow quality inputs
write_cell(ss, co, CO$avg + 4L, 2, glue('="The story is in the yellow quality inputs: the weakest cohort is #"&MATCH(MIN({q_rng}),{q_rng},0)&" (quality "&TEXT(MIN({q_rng}),"0.00")&"), the strongest #"&MATCH(MAX({q_rng}),{q_rng},0)&" ("&TEXT(MAX({q_rng}),"0.00")&")."'))
# Retention-curve feed for the chart below: weighted average, best and weakest cohort quality (all 12 months numeric).
write_cell(ss, co, CO$feed, 2, "CHART FEED (drives the curves below; do not edit)")
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
write_cell(ss, ue, U$sub, 2, '="Sample data  |  Scenario: "&scenario&"  |  Year 1 = month 12, Year 2 = month 24"')
write_cell(ss, ue, U$leg, 2, "Every figure is a formula over the Forecast tab. Yellow rule-of-thumb cells are rough SaaS benchmarks you can change; Status tests year 2 against them.")
for (j in 1:7) write_cell(ss, ue, U$hdr, 1L + j, c("Metric", "Year 1", "Year 2", "", "Rule of thumb", "Status (year 2)", "How it is calculated")[j])
write_cell(ss, ue, U$s_acq, 2, "ACQUISITION"); write_cell(ss, ue, U$s_ltv, 2, "LIFETIME VALUE"); write_cell(ss, ue, U$s_ret, 2, "RETENTION AND GROWTH")
UL <- list(
  new = c("New customers in the year", "Sum of new customers over the 12 months"),
  cac = c("CAC ($, equals the input)", "S&M spend / new customers (the CAC input, by design)"),
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
  write_cell(ss, ue, U$cac,    cc, glue('=IF(Forecast!{Y}{r$c_new}=0,"",Forecast!{Y}{r$sm}/Forecast!{Y}{r$c_new})'))
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
write_cell(ss, sn, 2, 2, "Scenarios")
write_cell(ss, sn, 3, 2, '="Sample data  |  Base, Upside and Downside computed side by side  |  Selected scenario: "&scenario')
write_cell(ss, sn, 4, 2, "A second calculation of all three scenarios from the Assumptions columns. It feeds the Summary comparison and ARR chart; Checks proves the selected one matches the Forecast.")
write_cell(ss, sn, SE$hdr, 2, "Line item"); write_cell(ss, sn, SE$hdr, 3, "Start")
write_cell(ss, sn, SE$mnum, 2, "Month number"); write_cell(ss, sn, SE$mnum, 3, 0L)
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
  write_cell(ss, sn, R("churn") - 1L, 2, toupper(SCN[s]))                                   # block bar
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
# the selected one again (drawn bold) and two year-end markers. Marker cells stay empty elsewhere (a gap, not a zero).
write_cell(ss, sn, SE$feed, 2, "CHART FEED (drives the Summary ARR chart; do not edit)")
write_cell(ss, sn, SE_F$date, 3, "Month")
for (s in 1:3) write_cell(ss, sn, c(SE_F$base, SE_F$up, SE_F$down)[s], 3, SCN[s])
write_cell(ss, sn, SE_F$sel, 3, '="Selected: "&scenario'); write_cell(ss, sn, SE_F$mark, 3, "Month 12 and 24")
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
  list("Summary ARR card = Forecast ARR, month 24", "=Summary!B9", glue("=Forecast!{M24}{r$arr}"), "eq"),
  list("Unit Economics LTV : CAC = Forecast LTV : CAC, month 24", glue("={XU}!D{U$ltvcac}"), glue("=Forecast!{M24}{r$ltv_cac}"), "eq"),
  list("No error values on any model tab (Summary included)",
       glue("=SUMPRODUCT(--ISERROR(Forecast!A1:AD{max(unlist(r))}))+SUMPRODUCT(--ISERROR({XB}!A1:G{B$feed + 5L}))+SUMPRODUCT(--ISERROR(Cohorts!A1:Q{CO$feed + 4L}))+SUMPRODUCT(--ISERROR({XU}!A1:H{U$magic}))+SUMPRODUCT(--ISERROR(Assumptions!A1:H{A_LAST}))+SUMPRODUCT(--ISERROR(Scenarios!A1:AA{SE_F$mark}))+SUMPRODUCT(--ISERROR(Summary!B2:M4))+SUMPRODUCT(--ISERROR(Summary!B8:M{SU$about + 6L}))"), "=0", "eq"))
WARNS <- list(
  list("Cash stays positive (lowest month-end balance)", glue("=MIN(Forecast!C{r$cash_close}:{M24}{r$cash_close})"), "=0", "ge"),
  list("Customer count stays positive (lowest month-end)", glue("=MIN(Forecast!C{r$c_close}:{M24}{r$c_close})"), "=0", "ge"))
CK_FIRST <- 7L; CK_LAST <- CK_FIRST + length(CHECKS) - 1L
W_BAR <- CK_LAST + 2L; W_FIRST <- W_BAR + 1L; W_LAST <- W_FIRST + length(WARNS) - 1L
write_cell(ss, ck, 2, 2, "Model checks")
write_cell(ss, ck, 3, 2, "Sample data  |  Every integrity row must read PASS and feeds the badge on Summary. Warnings below depend on the inputs and do not.")
write_cell(ss, ck, 4, 3, "Overall status")
write_cell(ss, ck, 4, 4, glue('=IF(COUNTIF(G{CK_FIRST}:G{CK_LAST},"FAIL")=0,"Model ties: OK","Model ties: CHECK")'))
write_cell(ss, ck, 4, 6, "Tolerance (fixed)"); write_cell(ss, ck, 4, 7, 0.01)
write_cell(ss, ck, 5, 3, glue('=COUNTIF(G{CK_FIRST}:G{CK_LAST},"PASS")&" of "&ROWS(G{CK_FIRST}:G{CK_LAST})&" integrity checks pass"'))
write_cell(ss, ck, 5, 6, "Warnings"); write_cell(ss, ck, 5, 7, glue('=COUNTIF(G{W_FIRST}:G{W_LAST},"WARN")'))
for (j in 1:6) write_cell(ss, ck, 6, 1L + j, c("#", "Check", "Model value", "Expected", "Difference", "Status")[j])
write_cell(ss, ck, W_BAR, 2, "BUSINESS WARNINGS  |  they depend on the inputs and never change the model status")
ck_row <- function(rw, i, cx, bad) {
  write_cell(ss, ck, rw, 2, i); write_cell(ss, ck, rw, 3, cx[[1]]); write_cell(ss, ck, rw, 4, cx[[2]]); write_cell(ss, ck, rw, 5, cx[[3]])
  write_cell(ss, ck, rw, 6, if (cx[[4]] == "eq") glue('=IF((D{rw}="")<>(E{rw}=""),1,ROUND(D{rw}-E{rw},4))')   # blank vs number is a difference, blank = blank ties
                            else glue("=MIN(0,ROUND(D{rw}-E{rw},4))"))
  write_cell(ss, ck, rw, 7, glue('=IFERROR(IF(ABS(F{rw})<=check_tol,"PASS","{bad}"),"{bad}")'))
}
for (i in seq_along(CHECKS)) ck_row(CK_FIRST + i - 1L, i, CHECKS[[i]], "FAIL")
for (i in seq_along(WARNS))  ck_row(W_FIRST + i - 1L, i, WARNS[[i]], "WARN")

## ---- Summary ----------------------------------------------------------------
sm <- TAB[["sum"]]
ARR24 <- glue("Forecast!{M24}{r$arr}"); CASH24 <- glue("Forecast!{M24}{r$cash_close}")
EBQ <- glue("AVERAGE(Forecast!{mcol(22L)}{r$ebitda}:{M24}{r$ebitda})")     # average EBITDA of the last 3 months
BE_F <- glue("MATCH(TRUE,ARRAYFORMULA(Forecast!D{r$ebitda}:{M24}{r$ebitda}>0),0)")
write_cell(ss, sm, 2, 2, "SaaS Financial Model - Sample Data"); write_cell(ss, sm, 2, 11, "SAMPLE DATA")
write_cell(ss, sm, 3, 2, glue('=scenario&": ARR reaches "&TEXT({ARR24}/1000000,"$0.0")&"M by month 24 ("&TEXT({ARR24}/Forecast!{M12}{r$arr}-1,"+0%;-0%")&" vs month 12); "&IFERROR("EBITDA positive from month "&{BE_F},"EBITDA stays negative")&"; "&IF({CASH24}<=0,"cash runs out","cash ends at "&TEXT({CASH24}/1000000,"$0.00")&"M")&"."'))
write_cell(ss, sm, 5, 2, "SCENARIO"); write_cell(ss, sm, 5, 3, "Base")
write_cell(ss, sm, 5, 5, "BRIDGE PERIOD"); write_cell(ss, sm, 5, 7, "Year 1")
write_cell(ss, sm, 5, 10, "MODEL CHECK"); write_cell(ss, sm, 5, 11, "=model_status")
write_cell(ss, sm, 6, 2, "Input"); write_cell(ss, sm, 6, 3, "All other cells are formulas")
write_cell(ss, sm, 6, 5, "Scenario drives every tab and chart. Bridge period only changes the waterfall.")
write_cell(ss, sm, 6, 11, '=IF(model_warnings=0,"","See Checks: "&model_warnings&IF(model_warnings=1," warning"," warnings"))')
KPI <- list(
  list("ARR (MONTH 24)", glue("={ARR24}"), NF_ARR_M,
       glue('=TEXT({ARR24}/Forecast!{M12}{r$arr}-1,"+0%;-0%")&" vs month 12"'), "arr"),
  list("MRR GROWTH, MoM (YEAR 2)", glue("=Forecast!AD{r$m_growth}"), NF_PCT1,
       glue('="Year 1: "&TEXT(Forecast!AC{r$m_growth},"0.0%")'), "m_growth"),
  list("NRR (YEAR 2)", glue("={XU}!D{U$nrr}"), NF_PCT0,
       glue('="GRR "&TEXT({XU}!D{U$grr},"0%")&" (year 2)"'), "ret_net"),
  list("GROSS MARGIN (M24)", glue("=Forecast!{M24}{r$gm_pct}"), NF_PCT1,
       glue('="Month 1: "&TEXT(Forecast!D{r$gm_pct},"0.0%")'), "gm_pct"),
  list("CASH RUNWAY (M24)",
       glue('=IF({CASH24}<=0,"Cash out",IF({EBQ}>=0,"Self-funded",IF({CASH24}/-{EBQ}>runway_cap,runway_cap&"+ mo",ROUND({CASH24}/-{EBQ},0))))'),
       NF('0" mo"'),
       glue('="Cash at month 24: "&TEXT({CASH24}/1000000,"$0.00")&"M"'), "cash_close"),
  list("LTV : CAC (M24)", glue('=IF({XU}!D{U$ltvcac}="","n/a",{XU}!D{U$ltvcac})'), NF_X,           # "n/a" when churn is 0 (LTV undefined)
       glue('="Payback "&TEXT({XU}!D{U$payback},"0")&" months"'), "ltv_cac"))
for (i in seq_along(KPI)) {
  c0 <- 2L + 2L * (i - 1L); kp <- KPI[[i]]
  write_cell(ss, sm, 8, c0, kp[[1]]); write_cell(ss, sm, 9, c0, kp[[2]]); write_cell(ss, sm, 10, c0, kp[[4]])
  write_cell(ss, sm, 11, c0, f_sparkline(glue("Forecast!D{r[[kp[[5]]]]}:{M24}{r[[kp[[5]]]]}"),
                                         list(charttype = "line", linewidth = 2, color = color_to_hex(COL_BRAND)),
                                         iferror = TRUE))   # iferror: a SPARKLINE over an all-blank row (LTV:CAC when churn is 0) is #N/A
}
write_cell(ss, sm, 13, 2, glue('="MRR BRIDGE  |  "&bridge_period&"  |  "&scenario&"  |  net new "&TEXT({XB}!G{B$netpct},"+0%;-0%")&" of opening"'))
write_cell(ss, sm, 13, 8, '="ARR TREND  |  all scenarios  |  "&scenario&" in bold"')
write_cell(ss, sm, 32, 2, '="MONTHLY MRR MOVEMENTS  |  "&scenario&" scenario"'); write_cell(ss, sm, 32, 9, "ANNUAL SNAPSHOT")
write_cell(ss, sm, 33, 9, "Metric"); write_cell(ss, sm, 33, 11, "Year 1"); write_cell(ss, sm, 33, 12, "Year 2"); write_cell(ss, sm, 33, 13, "YoY")
SNAP <- list(list("Revenue", "rev", NF_K), list("Gross profit", "gp", NF_K), list("Operating expenses", "opex", NF_K),
             list("EBITDA", "ebitda", NF_K), list("Closing ARR", "arr", NF_K),
             list("Closing customers", "c_close", NF_INT), list("Closing cash", "cash_close", NF_K))
for (i in seq_along(SNAP)) {
  rw <- 33L + i; sp <- SNAP[[i]]
  write_cell(ss, sm, rw, 9, sp[[1]])
  write_cell(ss, sm, rw, 11, glue("=Forecast!AC{r[[sp[[2]]]]}")); write_cell(ss, sm, rw, 12, glue("=Forecast!AD{r[[sp[[2]]]]}"))
  write_cell(ss, sm, rw, 13, glue('=IF(K{rw}<=0,"n/m",L{rw}/K{rw}-1)'))
}
HOWTO <- c("How to use this sample", "1  Pick a scenario above: every tab, KPI and chart updates.",
           "2  Pick a bridge period: it changes the MRR waterfall only.", "3  Yellow cells on Assumptions are the inputs.",
           "4  The Checks tab proves the model ties (badge above).", "5  To edit anything: File > Make a copy.")
for (i in seq_along(HOWTO)) write_cell(ss, sm, 41L + i, 9, HOWTO[i])
# Scenario comparison: all three scenarios from the Scenarios tab, the selected one highlighted
CMP_COL <- c(5L, 8L, 11L)                                    # first column of the Base / Upside / Downside blocks
write_cell(ss, sm, SU$cmp, 2, '="SCENARIO COMPARISON  |  all three side by side  |  "&scenario&" is highlighted"')
write_cell(ss, sm, SU$cmp_hdr, 2, "Metric")
for (s in 1:3) write_cell(ss, sm, SU$cmp_hdr, CMP_COL[s], SCN[s])
CMP <- list(
  list("ARR, month 24",         function(s) glue("=Scenarios!{M24}{se_row(s, 'arr')}"), NF_ARR_M),
  list("ARR growth, year 2",    function(s) glue('=IFERROR(Scenarios!{M24}{se_row(s, "arr")}/Scenarios!{M12}{se_row(s, "arr")}-1,"")'), NF('+0%;-0%')),
  list("Customers, month 24",   function(s) glue("=Scenarios!{M24}{se_row(s, 'cust')}"), NF_INT),
  list("EBITDA, year 2",        function(s) glue("=SUM(Scenarios!{mcol(13L)}{se_row(s, 'ebitda')}:{M24}{se_row(s, 'ebitda')})"), NF_K),
  list("EBITDA positive from",  function(s) glue('=IFERROR(MATCH(TRUE,ARRAYFORMULA(Scenarios!D{se_row(s, "ebitda")}:{M24}{se_row(s, "ebitda")}>0),0),"Not in 24 months")'), NF('"Month "0')),
  list("Cash, month 24",        function(s) glue("=Scenarios!{M24}{se_row(s, 'cash')}"), NF_CASH_M),
  list("LTV : CAC, month 24",   function(s) glue("=Scenarios!{M24}{se_row(s, 'ltvcac')}"), NF_X))
for (i in seq_along(CMP)) {
  rw <- SU$cmp_first + i - 1L
  write_cell(ss, sm, rw, 2, CMP[[i]][[1]])
  for (s in 1:3) write_cell(ss, sm, rw, CMP_COL[s], CMP[[i]][[2]](s))
}
write_cell(ss, sm, SU$cmp_note, 2, "Computed on the Scenarios tab from the three Assumptions columns; Checks proves the selected one matches the Forecast.")
write_cell(ss, sm, SU$about, 2, "ABOUT THIS SAMPLE")
write_cell(ss, sm, SU$about + 1L, 2, "Sample data only. Every figure is synthetic and generated by a seeded script; no real company, customer, person or amount. Illustrative, not advice.")
write_cell(ss, sm, SU$about + 2L, 2, "Built with the r-googlesheets4 skill (open source, MIT licence):")
write_cell(ss, sm, SU$about + 4L, 2, "Built on googlesheets4 (Jennifer Bryan), gargle (Jennifer Bryan, Craig Citro, Hadley Wickham) and googledrive (Lucy D'Agostino McGowan, Jennifer Bryan); all Posit Software, PBC:")
write_cell(ss, sm, SU$about + 6L, 2, "Unofficial add-on, not affiliated with or endorsed by Posit or Google. Rebuild script: examples/showcases/saas-model.R")

flush_writes(ss, strict = TRUE)
Sys.sleep(3)    # let the backend commit values before formatting

# =============================================================================
# 2. FORMATTING, per tab (one atomic batch each, strict)
# =============================================================================
## ---- Assumptions ------------------------------------------------------------
S <- sid[["asm"]]; n <- GRID$asm
grp_rows <- unname(unlist(A_ROWS[grepl("^grp_", names(A_ROWS))]))
DRV_SIGNED <- c("new_cust_growth", "churn_improve", "gm_gain_per_year", "opex_growth")   # rates that may legitimately be negative
fmt_asm <- c(
  list(fmt_gridlines(S, FALSE), fmt_freeze(S, rows = A_HDR), fmt_tab_color(S, COL_WARNING),
       tab_base(S, n),
       fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 2, 270), fmt_col_width(S, 3, 3, 126),
       fmt_col_width(S, 4, 6, 112), fmt_col_width(S, 7, 7, 150), fmt_col_width(S, 8, 8, 400),
       fmt_row_height(S, 1, 1, 10), fmt_row_height(S, 2, 2, 40), fmt_row_height(S, 3, 3, 22),
       fmt_row_height(S, 4, 4, 26), fmt_row_height(S, A_HDR, A_HDR, 30),
       fmt_cells(S, 2, 2, 2, 2, font_size = 24, bold = TRUE, font_color = COL_BRAND),
       fmt_cells(S, 3, 3, 2, 2, font_size = 11, italic = TRUE, font_color = COL_MUTED),
       fmt_cells(S, 4, 4, 2, 2, font_size = 10, bold = TRUE, font_color = COL_MUTED),
       fmt_cells(S, 4, 4, 3, 3, font_size = 10, bold = TRUE, font_color = COL_BRAND, bg_color = COL_INPUT, halign = "CENTER"),
       fmt_cells(S, 4, 4, 4, 4, font_size = 10, font_color = COL_MUTED, bg_color = COL_CALC, halign = "CENTER"),
       fmt_cells(S, A_HDR, A_HDR, 2, 8, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, valign = "MIDDLE"),
       fmt_cells(S, A_HDR, A_HDR, 3, 6, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "CENTER"),
       # model settings band + rows
       fmt_cells(S, A_BAND, A_BAND, 2, 8, font_size = 11, bold = TRUE, font_color = COL_BRAND_DEEP, bg_color = COL_BRAND_SUBTLE),
       fmt_cells(S, A_SCN, A_FIRST, 2, 2, font_size = 11),
       fmt_cells(S, A_SCN, A_SCN, 3, 3, font_size = 11, bold = TRUE, font_color = COL_INK, bg_color = COL_CALC, halign = "CENTER"),
       fmt_cells(S, A_FIRST, A_FIRST, 3, 3, font_size = 11, bold = TRUE, font_color = COL_BRAND, bg_color = COL_INPUT, halign = "RIGHT",
          numfmt = NF("mmm yyyy", "DATE")),
       fmt_cells(S, A_SCN, A_FIRST, 7, 8, font_size = 10, italic = TRUE, font_color = COL_MUTED)),
  lapply(grp_rows, function(g) fmt_cells(S, g, g, 2, 8, font_size = 11, bold = TRUE, font_color = COL_BRAND_DEEP, bg_color = COL_BRAND_SUBTLE)),
  unlist(lapply(seq_len(nrow(DRV)), function(i) {
    rw <- A_ROWS[[DRV$name[i]]]
    nf <- switch(DRV$nf[i], int = NF('#,##0_)_)_)'), usd = NF('$#,##0_)_)_)'), pct = NF('0.0%_)_)_)', "PERCENT"),
                 mo = NF('0" mo"_)_)_)'))             # trailing pad keeps numbers off the Unit text
    dv <- if (DRV$nf[i] != "pct") list("NUMBER_GREATER_THAN_EQ", 0, "Enter a number, 0 or more.")   # counts, dollars, months
          else if (DRV$name[i] %in% DRV_SIGNED) list("NUMBER_BETWEEN", c(-1, 1), "Enter a percentage from -100% to 100%.")
          else list("NUMBER_BETWEEN", c(0, 1), "Enter a percentage from 0% to 100%.")
    list(fmt_cells(S, rw, rw, 3, 3, font_size = 11, bold = TRUE, font_color = COL_INK, bg_color = COL_CALC, numfmt = nf, halign = "RIGHT"),
         fmt_cells(S, rw, rw, 4, 6, font_size = 11, font_color = COL_BRAND, bg_color = COL_INPUT, numfmt = nf, halign = "RIGHT"),
         fmt_cells(S, rw, rw, 7, 8, font_size = 10, italic = TRUE, font_color = COL_MUTED),
         ln(S, rw, rw, 2, 8),
         fmt_validation(S, rw, rw, 4, 6, dv[[1]], dv[[2]], input_message = dv[[3]]))
  }), recursive = FALSE),
  # highlight the active scenario header; CF cannot use a name that lives on another tab, so it reads C7
  list(fmt_cond_formula(S, A_HDR, A_HDR, 4, 6, glue("=D${A_HDR}=$C${A_SCN}"), bg_color = hex_to_color("137333")),   # dark green: white text stays above 4.5:1
       fmt_validation(S, A_FIRST, A_FIRST, 3, 3, "DATE_IS_VALID", input_message = "Enter a date, for example 2027-01-01."),
       fmt_protected_range(S, description = "Formulas: edit only the yellow input cells",
                           unprotected_ranges = list(grid_range(S, A_FIRST, A_FIRST, 3, 3), grid_range(S, A_FIRST + 1L, A_LAST, 4, 6)))))

## ---- Forecast ---------------------------------------------------------------
S <- sid[["fc"]]; n <- GRID$fc; LASTC <- COL_Y2
k1_keys <- c("m_open", "m_new", "m_exp", "m_con", "m_churn", "m_close")       # one decimal: contraction is small
money_keys <- c("arr", "rev", "cogs", "gp", "sm", "rd",
                "ga", "opex", "ebitda", "cash_open", "cash_flow", "cash_close")
rowfmt <- function(keys, nf, ...) lapply(keys, function(k) fmt_cells(S, r[[k]], r[[k]], 3, LASTC, numfmt = nf, halign = "RIGHT", ...))
emph <- c("c_close", "m_close", "arr", "gp", "ebitda", "cash_close")
fmt_fc <- c(
  list(fmt_gridlines(S, TRUE), fmt_freeze(S, rows = r$mnum, cols = 2), fmt_tab_color(S, COL_BRAND_DEEP),
       tab_base(S, n, 10),
       fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 2, 235), fmt_col_width(S, 3, 3, 92),
       fmt_col_width(S, 4, 27, 68), fmt_col_width(S, 28, 28, 14), fmt_col_width(S, 29, 30, 86),
       fmt_row_height(S, r$title, r$title, 36), fmt_row_height(S, r$sub, r$sub, 22),
       fmt_row_height(S, r$hdr, r$hdr, 26), fmt_row_height(S, r$mnum, r$mnum, 18),
       fmt_cells(S, r$title, r$title, 2, 2, font_size = 22, bold = TRUE, font_color = COL_BRAND),
       fmt_cells(S, r$sub, r$sub, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED)),
  rowfmt(money_keys, NF_K), rowfmt(k1_keys, NF('$#,##0.0,"K";($#,##0.0,"K");"-"')), rowfmt(c("c_open", "c_new", "c_churn", "c_close"), NF_INT),
  rowfmt("churn", NF_PCT2), rowfmt(c("gm", "m_growth", "ret_net", "ret_gross", "gm_pct", "ebitda_pct"), NF_PCT1),
  rowfmt(c("arpa", "ltv"), NF_USD), rowfmt("ltv_cac", NF_X),
  # all four movement rows MUST share one number format: the chart's left axis takes its format from them
  # (mixed formats made the axis fall back to plain 20000 / -10000)
  rowfmt(c("f_new", "f_exp", "f_con", "f_churn"), NF_AXIS_K),
  list(fmt_cells(S, r$f_month, r$f_churn, 3, LASTC, halign = "RIGHT"),
       fmt_cells(S, r$f_month, r$f_churn, 2, LASTC, font_size = 10, font_color = COL_MUTED)),
  # Start column and Year totals
  list(fmt_cells(S, r$churn, r$f_churn, 3, 3, font_size = 10, italic = TRUE, font_color = COL_MUTED, halign = "RIGHT")),
  lapply(emph, function(k) fmt_cells(S, r[[k]], r[[k]], 2, LASTC, font_size = 10, bold = TRUE, italic = FALSE, font_color = COL_INK, bg_color = COL_BRAND_SUBTLE)),   # upright ink where they cross the italic Start column
  lapply(emph, function(k) ln(S, r[[k]], r[[k]], 2, LASTC, "top", "SOLID", COL_BRAND)),
  list(fmt_cells(S, r$churn, r$ltv_cac, COL_Y1, COL_Y2, font_size = 10, bold = TRUE, bg_color = COL_LIGHT_GRAY)),
  lapply(c("s_drv", "s_cust", "s_mrr", "s_pl", "s_cash", "s_ue", "s_feed"), function(k)
    fmt_cells(S, r[[k]], r[[k]], 2, LASTC, font_size = 10, bold = TRUE, italic = FALSE, font_color = COL_WHITE, bg_color = COL_BRAND)),
  list(fmt_cells(S, r$hdr, r$hdr, 2, LASTC, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "RIGHT"),
       fmt_cells(S, r$hdr, r$hdr, 2, 2, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT"),
       fmt_cells(S, r$mnum, r$mnum, 2, LASTC, font_size = 9, italic = TRUE, font_color = COL_MUTED, bg_color = COL_LIGHT_GRAY, halign = "RIGHT"),
       fmt_cells(S, r$mnum, r$mnum, 2, 2, font_size = 9, italic = TRUE, font_color = COL_MUTED, bg_color = COL_LIGHT_GRAY, halign = "LEFT"),
       fmt_cond_negative(S, r$s_drv, r$ltv_cac, 3, LASTC, color = COL_NEGATIVE),
       fmt_protected_range(S, description = "Forecast is formula-driven; change inputs on Assumptions")))

## ---- MRR Bridge -------------------------------------------------------------
S <- sid[["br"]]; n <- GRID$br
fmt_br <- list(
  fmt_gridlines(S, FALSE), fmt_freeze(S, rows = B$hdr), fmt_tab_color(S, hex_to_color("0F9D8A")),
  tab_base(S, n),
  fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 2, 214), fmt_col_width(S, 3, 5, 98),
  fmt_col_width(S, 6, 6, 12), fmt_col_width(S, 7, 7, 132), fmt_col_width(S, 8, 8, 20),
  fmt_row_height(S, 1, 1, 10), fmt_row_height(S, 2, 2, 40), fmt_row_height(S, 3, 3, 22),
  fmt_row_height(S, 4, 5, 22), fmt_row_height(S, B$hdr, B$hdr, 30),
  fmt_cells(S, 2, 2, 2, 2, font_size = 24, bold = TRUE, font_color = COL_BRAND),
  fmt_cells(S, 3, 3, 2, 2, font_size = 11, italic = TRUE, font_color = COL_MUTED),
  fmt_cells(S, 4, 4, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED),
  fmt_cells(S, B$hdr, B$hdr, 2, 7, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "RIGHT"),
  fmt_cells(S, B$hdr, B$hdr, 2, 2, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT"),
  fmt_cells(S, B$open, B$diff, 7, 7, bg_color = COL_BRAND_SUBTLE),
  fmt_cells(S, B$from, B$to, 2, 7, font_size = 10, italic = TRUE, font_color = COL_MUTED),
  fmt_cells(S, B$from, B$to, 3, 7, numfmt = NF('0'), halign = "RIGHT"),
  fmt_cells(S, B$open, B$close, 3, 7, numfmt = NF_USD, halign = "RIGHT"),
  fmt_cells(S, B$net, B$net, 3, 7, numfmt = NF_USD, halign = "RIGHT"),
  fmt_cells(S, B$netpct, B$netpct, 3, 7, numfmt = NF_PCT1, halign = "RIGHT"),
  fmt_cells(S, B$tie, B$diff, 3, 7, numfmt = NF_USD, halign = "RIGHT"),
  fmt_cells(S, B$tie, B$diff, 2, 7, font_size = 10, italic = TRUE, font_color = COL_MUTED),
  fmt_cells(S, B$open, B$open, 2, 7, font_size = 11, bold = TRUE),
  fmt_cells(S, B$close, B$close, 2, 7, font_size = 11, bold = TRUE, bg_color = COL_BRAND_SUBTLE),
  ln(S, B$close, B$close, 2, 7, "top", "SOLID", COL_BRAND),
  ln(S, B$close, B$close, 2, 7, "bottom", "DOUBLE", COL_BRAND),
  fmt_cond_negative(S, B$open, B$diff, 3, 7, color = COL_NEGATIVE),
  fmt_row_height(S, B$feed_hdr, B$feed_hdr, 24),
  fmt_cells(S, B$feed_hdr, B$feed_hdr, 2, 7, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
  fmt_cells(S, B$feed, B$feed + 5L, 2, 3, font_size = 10, font_color = COL_MUTED),
  fmt_cells(S, B$feed, B$feed + 5L, 3, 3, numfmt = NF_USD0, halign = "RIGHT"),       # the chart axis takes this format: zero reads $0, not "-"
  fmt_protected_range(S, description = "Formulas: choose the scenario and period on Summary"))

## ---- Cohorts ----------------------------------------------------------------
S <- sid[["co"]]; n <- GRID$co; c_last <- CO$avg - 1L
fmt_co <- list(
  fmt_gridlines(S, FALSE), fmt_freeze(S, rows = CO$hdr), fmt_tab_color(S, hex_to_color("7C5CBF")),
  tab_base(S, n),
  fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 2, 44), fmt_col_width(S, 3, 3, 152),
  fmt_col_width(S, 4, 4, 112), fmt_col_width(S, 5, 5, 104), fmt_col_width(S, 6, 17, 58), fmt_col_width(S, 18, 18, 18),
  fmt_row_height(S, 1, 1, 10), fmt_row_height(S, 2, 2, 40), fmt_row_height(S, 3, 3, 22),
  fmt_row_height(S, 4, 4, 22), fmt_row_height(S, 5, 5, 24), fmt_row_height(S, CO$hdr, CO$hdr, 28),
  fmt_cells(S, 2, 2, 2, 2, font_size = 24, bold = TRUE, font_color = COL_BRAND),
  fmt_cells(S, 3, 3, 2, 2, font_size = 11, italic = TRUE, font_color = COL_MUTED),
  fmt_cells(S, 4, 4, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED),
  fmt_merge(S, 5, 5, 6, 17),
  fmt_cells(S, 5, 5, 6, 17, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "CENTER"),
  fmt_cells(S, CO$hdr, CO$hdr, 2, 17, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "CENTER"),
  fmt_cells(S, CO$hdr, CO$hdr, 3, 3, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT"),
  fmt_cells(S, CO$hdr, CO$hdr, 4, 4, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "RIGHT"),   # over right-aligned numbers
  fmt_cells(S, CO$hdr, CO$hdr, 6, 17, numfmt = NF('"M"0')),
  fmt_cells(S, CO$first, c_last, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED, halign = "CENTER"),
  fmt_cells(S, CO$first, c_last, 3, 3, font_size = 11, bold = TRUE, halign = "LEFT"),
  fmt_cells(S, CO$first, c_last, 4, 4, font_size = 11, numfmt = NF("#,##0.0"), halign = "RIGHT", bg_color = COL_CALC),   # 1 decimal so the column visibly sums
  fmt_cells(S, CO$first, c_last, 5, 5, font_size = 11, font_color = COL_BRAND, bg_color = COL_INPUT, numfmt = NF("0.00"), halign = "CENTER"),
  fmt_cells(S, CO$first, c_last, 6, 17, font_size = 10, numfmt = NF_PCT0, halign = "CENTER"),
  fmt_cells(S, CO$avg, CO$avg, 2, 17, font_size = 11, bold = TRUE, bg_color = COL_BRAND_SUBTLE),
  fmt_cells(S, CO$avg, CO$avg, 4, 4, numfmt = NF("#,##0.0"), halign = "RIGHT"),
  fmt_cells(S, CO$avg, CO$avg, 6, 17, numfmt = NF_PCT0, halign = "CENTER"),
  ln(S, CO$avg, CO$avg, 2, 17, "top", "SOLID", COL_BRAND),
  fmt_cells(S, CO$avg + 2L, CO$avg + 4L, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED),
  # M0 is always 100%: a flat green, so the scale spans M1..M11 and the rows (cohorts) visibly differ.
  # The average row shares the scale.
  fmt_cells(S, CO$first, c_last, 6, 6, bg_color = COL_GREEN_LIGHT),
  fmt_cond_color_scale(S, CO$first, CO$avg, 7, 17, min_color = COL_RED_LIGHT,
                       mid_color = COL_YELLOW_LIGHT, max_color = COL_GREEN_LIGHT),
  # retention-curve feed (visible, small, muted) and its chart below
  fmt_merge(S, CO$feed, CO$feed, 2, 17),
  fmt_cells(S, CO$feed, CO$feed, 2, 17, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
  fmt_cells(S, CO$feed + 1L, CO$feed + 4L, 5, 17, font_size = 10, font_color = COL_MUTED, halign = "CENTER"),
  fmt_cells(S, CO$feed + 1L, CO$feed + 4L, 5, 5, font_size = 10, bold = TRUE, font_color = COL_MUTED, halign = "LEFT"),
  fmt_cells(S, CO$feed + 1L, CO$feed + 1L, 6, 17, numfmt = NF('"M"0')),
  fmt_cells(S, CO$feed + 2L, CO$feed + 4L, 6, 17, numfmt = NF_PCT0),
  fmt_row_height(S, CO$feed, CO$feed, 24),
  fmt_validation(S, CO$first, c_last, 5, 5, "NUMBER_BETWEEN", c(0.05, 3), input_message = "Quality factor from 0.05 to 3 (higher = lower churn)."),
  fmt_protected_range(S, description = "Heatmap is formula-driven; edit only the yellow quality factors",
                      unprotected_ranges = grid_range(S, CO$first, c_last, 5, 5)))

## ---- Unit Economics ---------------------------------------------------------
S <- sid[["ue"]]; n <- GRID$ue
ue_nf <- list(new = NF_INT, cac = NF_USD, arpa = NF_USD, gm = NF_PCT1, churn = NF_PCT2, life = NF('0.0'),
              ltv = NF_USD, ltvcac = NF_X, payback = NF('0.0'), nrr = NF_PCT1, grr = NF_PCT1,
              growth = NF_PCT1, margin = NF_PCT1, r40 = NF_PCT1, magic = NF('0.00'))
ue_dv <- lapply(names(U_RULE), function(k) {                      # thresholds: shares stay 0-100%, the rest just must not be negative
  lo <- if (k == "r40") -1 else 0
  if (k %in% c("churn", "grr"))
    fmt_validation(S, U[[k]], U[[k]], 6, 6, "NUMBER_BETWEEN", c(0, 1), input_message = "Enter a percentage from 0% to 100%.")
  else
    fmt_validation(S, U[[k]], U[[k]], 6, 6, "NUMBER_GREATER_THAN_EQ", lo, input_message = paste0("Enter a number, ", lo, " or more."))
})
fmt_ue <- c(
  list(fmt_gridlines(S, FALSE), fmt_freeze(S, rows = U$hdr), fmt_tab_color(S, hex_to_color("5B8DEF")),
       tab_base(S, n),
       fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 2, 270), fmt_col_width(S, 3, 4, 120),
       fmt_col_width(S, 5, 5, 18), fmt_col_width(S, 6, 6, 112), fmt_col_width(S, 7, 7, 136), fmt_col_width(S, 8, 8, 400),
       fmt_row_height(S, 1, 1, 10), fmt_row_height(S, 2, 2, 40), fmt_row_height(S, 3, 3, 22),
       fmt_row_height(S, 4, 4, 22), fmt_row_height(S, U$hdr, U$hdr, 30),
       fmt_cells(S, 2, 2, 2, 2, font_size = 24, bold = TRUE, font_color = COL_BRAND),
       fmt_cells(S, 3, 3, 2, 2, font_size = 11, italic = TRUE, font_color = COL_MUTED),
       fmt_cells(S, 4, 4, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED),
       fmt_cells(S, U$hdr, U$hdr, 2, 8, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT"),
       fmt_cells(S, U$hdr, U$hdr, 3, 4, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "RIGHT"),
       fmt_cells(S, U$hdr, U$hdr, 6, 7, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "CENTER"),
       fmt_cells(S, U$hdr, U$hdr, 5, 5, bg_color = COL_WHITE)),
  lapply(c("s_acq", "s_ltv", "s_ret"), function(k) fmt_cells(S, U[[k]], U[[k]], 2, 8, font_size = 11, bold = TRUE, font_color = COL_BRAND_DEEP, bg_color = COL_BRAND_SUBTLE)),
  unlist(lapply(names(ue_nf), function(k)
    list(fmt_cells(S, U[[k]], U[[k]], 3, 4, font_size = 11, bold = TRUE, numfmt = ue_nf[[k]], halign = "RIGHT", bg_color = COL_CALC),
         fmt_cells(S, U[[k]], U[[k]], 2, 2, font_size = 11),
         fmt_cells(S, U[[k]], U[[k]], 8, 8, font_size = 10, italic = TRUE, font_color = COL_MUTED),
         ln(S, U[[k]], U[[k]], 2, 8))), recursive = FALSE),
  list(fmt_cells(S, U$ltvcac, U$ltvcac, 2, 2, font_size = 12, bold = TRUE),
       fmt_cells(S, U$ltvcac, U$ltvcac, 3, 4, font_size = 12, bold = TRUE, numfmt = NF_X, halign = "RIGHT", bg_color = COL_CALC)),
  # rules of thumb are yellow inputs shown as text ("< 2%"); Status tests year 2 against them
  unlist(lapply(names(U_RULE), function(k)
    list(fmt_cells(S, U[[k]], U[[k]], 6, 6, font_size = 10, font_color = COL_BRAND, bg_color = COL_INPUT, numfmt = NF(U_RULE[[k]][[3]]), halign = "CENTER"),
         fmt_cells(S, U[[k]], U[[k]], 7, 7, font_size = 10, bold = TRUE, halign = "CENTER"))), recursive = FALSE),
  ue_dv,
  list(fmt_cond_text_equals(S, U$churn, U$magic, 7, 7, "On track", bg_color = COL_GREEN_LIGHT, font_color = COL_GREEN_TXT, bold = TRUE),
       fmt_cond_text_equals(S, U$churn, U$magic, 7, 7, "Watch", bg_color = COL_WARNING_SOFT, font_color = COL_AMBER_TEXT, bold = TRUE),
       fmt_protected_range(S, description = "Formulas: only the yellow rule-of-thumb cells are inputs",
                           unprotected_ranges = lapply(names(U_RULE), function(k) grid_range(S, U[[k]], U[[k]], 6, 6)))))

## ---- Scenarios --------------------------------------------------------------
S <- sid[["sn"]]; n <- GRID$sn; LASTC <- 3L + N_M
SE_NF <- list(churn = NF_PCT2, new = NF("#,##0.0"), cust = NF_INT, mrr = NF_K, arr = NF_ARR_M, rev = NF_K,
              gm = NF_PCT1, ebitda = NF_K, cash = NF_K, ltvcac = NF_X)
fmt_sn <- c(
  list(fmt_gridlines(S, TRUE), fmt_freeze(S, rows = SE$mnum, cols = 2), fmt_tab_color(S, hex_to_color("E8710A")),
       tab_base(S, n, 10),
       fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 2, 235), fmt_col_width(S, 3, 3, 130),
       fmt_col_width(S, 4, LASTC, 68), fmt_col_width(S, LASTC + 1L, LASTC + 1L, 18),
       fmt_row_height(S, 1, 1, 10), fmt_row_height(S, 2, 2, 36), fmt_row_height(S, 3, 4, 22),
       fmt_row_height(S, SE$hdr, SE$hdr, 26), fmt_row_height(S, SE$mnum, SE$mnum, 18),
       fmt_cells(S, 2, 2, 2, 2, font_size = 22, bold = TRUE, font_color = COL_BRAND),
       fmt_cells(S, 3, 3, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED),
       fmt_cells(S, 4, 4, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED),
       fmt_cells(S, SE$hdr, SE$hdr, 2, LASTC, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "RIGHT"),
       fmt_cells(S, SE$hdr, SE$hdr, 2, 2, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT"),
       fmt_cells(S, SE$mnum, SE$mnum, 2, LASTC, font_size = 9, italic = TRUE, font_color = COL_MUTED, bg_color = COL_LIGHT_GRAY, halign = "RIGHT"),
       fmt_cells(S, SE$mnum, SE$mnum, 2, 2, font_size = 9, italic = TRUE, font_color = COL_MUTED, bg_color = COL_LIGHT_GRAY, halign = "LEFT")),
  unlist(lapply(1:3, function(s) {
    bar <- se_row(s, "churn") - 1L
    c(list(fmt_cells(S, bar, bar, 2, LASTC, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT")),
      lapply(SE_K, function(k) fmt_cells(S, se_row(s, k), se_row(s, k), 3, LASTC, numfmt = SE_NF[[k]], halign = "RIGHT")),
      list(fmt_cells(S, se_row(s, "churn"), se_row(s, "ltvcac"), 3, 3, font_size = 10, italic = TRUE, font_color = COL_MUTED, halign = "RIGHT")),
      lapply(c("arr", "ebitda", "cash"), function(k) fmt_cells(S, se_row(s, k), se_row(s, k), 2, LASTC, font_size = 10, bold = TRUE, italic = FALSE, font_color = COL_INK, bg_color = COL_BRAND_SUBTLE)))
  }), recursive = FALSE),
  list(fmt_cond_negative(S, SE$first, se_row(3, "ltvcac"), 3, LASTC, color = COL_NEGATIVE),
       fmt_cells(S, SE$feed, SE$feed, 2, LASTC, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
       fmt_cells(S, SE_F$date, SE_F$mark, 2, LASTC, font_size = 10, font_color = COL_MUTED, halign = "RIGHT"),
       fmt_cells(S, SE_F$date, SE_F$mark, 2, 3, font_size = 10, bold = TRUE, font_color = COL_MUTED, halign = "LEFT"),
       fmt_cells(S, SE_F$date, SE_F$date, 4, LASTC, numfmt = NF("mmm yy", "DATE")),
       fmt_cells(S, SE_F$base, SE_F$mark, 4, LASTC, numfmt = NF_ARR_M),
       fmt_protected_range(S, description = "Formulas: nothing to edit on this tab")))

## ---- Checks -----------------------------------------------------------------
S <- sid[["ck"]]; n <- GRID$ck
fmt_ck <- list(
  fmt_gridlines(S, FALSE), fmt_freeze(S, rows = 0L), fmt_tab_color(S, COL_POSITIVE),   # no frozen rows: the table fits one screen and frozen rows eat phone height
  tab_base(S, n),
  fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 2, 40), fmt_col_width(S, 3, 3, 470),
  fmt_col_width(S, 4, 6, 136), fmt_col_width(S, 7, 7, 100),
  fmt_row_height(S, 1, 1, 10), fmt_row_height(S, 2, 2, 40), fmt_row_height(S, 3, 3, 22),
  fmt_row_height(S, 4, 4, 34), fmt_row_height(S, 5, 5, 22), fmt_row_height(S, 6, 6, 28),
  fmt_cells(S, 2, 2, 2, 2, font_size = 24, bold = TRUE, font_color = COL_BRAND),
  fmt_cells(S, 3, 3, 2, 2, font_size = 11, italic = TRUE, font_color = COL_MUTED),
  fmt_cells(S, 4, 4, 3, 3, font_size = 11, bold = TRUE, font_color = COL_MUTED, halign = "RIGHT"),
  fmt_merge(S, 4, 4, 4, 5),
  fmt_cells(S, 4, 4, 4, 5, font_size = 13, bold = TRUE, font_color = COL_INK, bg_color = COL_CALC, halign = "CENTER"),
  fmt_cells(S, 4, 4, 6, 6, font_size = 10, bold = TRUE, font_color = COL_MUTED, halign = "RIGHT"),
  fmt_cells(S, 4, 4, 7, 7, font_size = 11, bold = TRUE, font_color = COL_MUTED, bg_color = COL_CALC, halign = "CENTER", numfmt = NF("0.00")),   # a fixed constant, not an input
  fmt_cells(S, 5, 5, 3, 3, font_size = 10, italic = TRUE, font_color = COL_MUTED),
  fmt_cells(S, 5, 5, 6, 6, font_size = 10, bold = TRUE, font_color = COL_MUTED, halign = "RIGHT"),
  fmt_cells(S, 5, 5, 7, 7, font_size = 11, bold = TRUE, font_color = COL_MUTED, bg_color = COL_CALC, halign = "CENTER", numfmt = NF("0")),
  fmt_cells(S, 6, 6, 2, 7, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT"),
  fmt_cells(S, 6, 6, 4, 7, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "RIGHT"),
  fmt_merge(S, W_BAR, W_BAR, 2, 7), fmt_row_height(S, W_BAR, W_BAR, 28),
  fmt_cells(S, CK_FIRST, W_LAST, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED, halign = "CENTER"),
  fmt_cells(S, CK_FIRST, W_LAST, 3, 3, font_size = 11),
  fmt_cells(S, CK_FIRST, W_LAST, 4, 6, font_size = 11, numfmt = NF_CHK, halign = "RIGHT"),
  fmt_cells(S, CK_FIRST, W_LAST, 7, 7, font_size = 11, bold = TRUE, halign = "CENTER"),
  fmt_cells(S, W_BAR, W_BAR, 2, 7, font_size = 11, bold = TRUE, italic = FALSE, font_color = COL_AMBER_TEXT, bg_color = COL_WARNING_SOFT, halign = "LEFT"),   # bar over the row formats above
  ln(S, CK_FIRST, CK_LAST, 2, 7, "bottom", "SOLID", COL_RULE),
  ln(S, CK_FIRST, CK_LAST, 2, 7, "inner_h", "SOLID", COL_RULE),
  ln(S, W_FIRST, W_LAST, 2, 7, "bottom", "SOLID", COL_RULE),
  ln(S, W_FIRST, W_LAST, 2, 7, "inner_h", "SOLID", COL_RULE),
  fmt_cond_text_equals(S, CK_FIRST, W_LAST, 7, 7, "PASS", bg_color = COL_GREEN_LIGHT, font_color = COL_GREEN_TXT, bold = TRUE),
  fmt_cond_text_equals(S, CK_FIRST, W_LAST, 7, 7, "FAIL", bg_color = COL_RED_LIGHT, font_color = COL_RED_TXT, bold = TRUE),
  fmt_cond_text_equals(S, CK_FIRST, W_LAST, 7, 7, "WARN", bg_color = COL_WARNING_SOFT, font_color = COL_AMBER_TEXT, bold = TRUE),
  fmt_cond_formula(S, 4, 4, 4, 5, '=$D$4="Model ties: OK"', bg_color = COL_GREEN_LIGHT, font_color = COL_GREEN_TXT),
  fmt_cond_formula(S, 4, 4, 4, 5, '=$D$4<>"Model ties: OK"', bg_color = COL_RED_LIGHT, font_color = COL_RED_TXT),
  fmt_cond_number(S, 5, 5, 7, 7, 0, "greater", bg_color = COL_WARNING_SOFT, font_color = COL_AMBER_TEXT, bold = TRUE),
  fmt_protected_range(S, description = "Formulas only: nothing to edit on this tab"))

## ---- Summary ----------------------------------------------------------------
S <- sid[["sum"]]; n <- GRID$sum
card_cols <- 2L + 2L * (0:5)
RUNWAY_LOW <- sprintf('=OR($J$9="Cash out",AND(ISNUMBER($J$9),$J$9<INDIRECT("Assumptions!$C$%d")))', A_ROWS[["runway_warn"]])
cmp_last <- SU$cmp_first + length(CMP) - 1L
fmt_sum <- c(
  list(fmt_gridlines(S, FALSE), fmt_freeze(S, rows = 6), fmt_tab_color(S, COL_BRAND),
       tab_base(S, n),
       fmt_col_width(S, 1, 1, 18), fmt_col_width(S, 2, 13, 92), fmt_col_width(S, 14, 14, 18)),
  list(fmt_row_height(S, 1, 1, 10), fmt_row_height(S, 2, 2, 44), fmt_row_height(S, 3, 3, 24), fmt_row_height(S, 4, 4, 8),
       fmt_row_height(S, 5, 5, 34), fmt_row_height(S, 6, 6, 22), fmt_row_height(S, 7, 7, 12),
       fmt_row_height(S, 8, 8, 24), fmt_row_height(S, 9, 9, 44), fmt_row_height(S, 10, 10, 22),
       fmt_row_height(S, 11, 11, 42), fmt_row_height(S, 12, 12, 14), fmt_row_height(S, 13, 13, 28),
       fmt_row_height(S, 14, 31, 20), fmt_row_height(S, 32, 32, 28), fmt_row_height(S, 33, 47, 20),
       fmt_row_height(S, 48, 48, 14), fmt_row_height(S, SU$cmp, SU$cmp, 28), fmt_row_height(S, SU$cmp_hdr, SU$cmp_hdr, 24),
       fmt_row_height(S, SU$cmp_first, SU$cmp_note, 22), fmt_row_height(S, SU$cmp_note + 1L, SU$cmp_note + 1L, 14),
       fmt_row_height(S, SU$about, SU$about, 28), fmt_row_height(S, SU$about + 1L, SU$about + 6L, 22)),
  list(fmt_cells(S, 2, 2, 2, 2, font_size = 26, bold = TRUE, font_color = COL_BRAND),
       fmt_merge(S, 2, 2, 11, 13),
       fmt_cells(S, 2, 2, 11, 13, font_size = 10, bold = TRUE, font_color = COL_AMBER_TEXT, bg_color = COL_WARNING_SOFT, halign = "CENTER"),
       fmt_cells(S, 3, 3, 2, 2, font_size = 11, bold = TRUE, font_color = COL_BRAND_DEEP),     # the dynamic headline sentence
       # controls: labels sit right-aligned against their selector
       fmt_cells(S, 5, 5, 2, 2, font_size = 9, bold = TRUE, font_color = COL_MUTED, halign = "RIGHT"),
       fmt_merge(S, 5, 5, 5, 6),
       fmt_cells(S, 5, 5, 5, 6, font_size = 9, bold = TRUE, font_color = COL_MUTED, halign = "RIGHT"),
       fmt_cells(S, 5, 5, 10, 10, font_size = 9, bold = TRUE, font_color = COL_MUTED, halign = "RIGHT"),
       fmt_merge(S, 5, 5, 3, 4), fmt_merge(S, 5, 5, 7, 8), fmt_merge(S, 5, 5, 11, 13),
       fmt_cells(S, 5, 5, 3, 4, font_size = 12, bold = TRUE, font_color = COL_BRAND, bg_color = COL_INPUT, halign = "CENTER"),
       fmt_cells(S, 5, 5, 7, 8, font_size = 12, bold = TRUE, font_color = COL_BRAND, bg_color = COL_INPUT, halign = "CENTER"),
       fmt_cells(S, 5, 5, 11, 13, font_size = 12, bold = TRUE, font_color = COL_INK, bg_color = COL_CALC, halign = "CENTER"),
       fmt_borders(S, 5, 5, 3, 4, top = list(style = "SOLID", color = COL_BRAND), bottom = list(style = "SOLID", color = COL_BRAND),
                   left = list(style = "SOLID", color = COL_BRAND), right = list(style = "SOLID", color = COL_BRAND)),
       fmt_borders(S, 5, 5, 7, 8, top = list(style = "SOLID", color = COL_BRAND), bottom = list(style = "SOLID", color = COL_BRAND),
                   left = list(style = "SOLID", color = COL_BRAND), right = list(style = "SOLID", color = COL_BRAND)),
       fmt_cells(S, 6, 6, 2, 2, font_size = 9, bold = TRUE, font_color = COL_BRAND, bg_color = COL_INPUT, halign = "CENTER"),
       fmt_merge(S, 6, 6, 3, 4), fmt_merge(S, 6, 6, 5, 10), fmt_merge(S, 6, 6, 11, 13),
       fmt_cells(S, 6, 6, 3, 4, font_size = 9, italic = TRUE, font_color = COL_MUTED, halign = "LEFT"),
       fmt_cells(S, 6, 6, 5, 10, font_size = 9, italic = TRUE, font_color = COL_MUTED, halign = "LEFT"),
       fmt_cells(S, 6, 6, 11, 13, font_size = 9, bold = TRUE, font_color = COL_AMBER_TEXT, halign = "CENTER"),
       fmt_dropdown(S, 5, 5, 3, 3, c("Base", "Upside", "Downside")),
       fmt_dropdown(S, 5, 5, 7, 7, c("Year 1", "Year 2", "Full period")),
       fmt_cond_formula(S, 5, 5, 11, 13, '=$K$5="Model ties: OK"', bg_color = COL_GREEN_LIGHT, font_color = COL_GREEN_TXT),
       fmt_cond_formula(S, 5, 5, 11, 13, '=$K$5<>"Model ties: OK"', bg_color = COL_RED_LIGHT, font_color = COL_RED_TXT)),
  unlist(lapply(seq_along(KPI), function(i) {
    c0 <- card_cols[i]; c1 <- c0 + 1L
    list(fmt_merge(S, 8, 8, c0, c1), fmt_merge(S, 9, 9, c0, c1), fmt_merge(S, 10, 10, c0, c1), fmt_merge(S, 11, 11, c0, c1),
         fmt_cells(S, 8, 11, c0, c1, bg_color = COL_BRAND_SUBTLE, halign = "CENTER"),
         fmt_cells(S, 8, 8, c0, c1, font_size = 9, bold = TRUE, font_color = COL_MUTED, bg_color = COL_BRAND_SUBTLE, halign = "CENTER"),
         fmt_cells(S, 9, 9, c0, c1, font_size = 20, bold = TRUE, font_color = COL_BRAND_DEEP, bg_color = COL_BRAND_SUBTLE, numfmt = KPI[[i]][[3]], halign = "CENTER"),
         fmt_cells(S, 10, 10, c0, c1, font_size = 9, font_color = COL_MUTED, bg_color = COL_BRAND_SUBTLE, halign = "CENTER"),
         fmt_borders(S, 8, 11, c0, c1, left = list(style = "SOLID_THICK", color = COL_WHITE),
                     right = list(style = "SOLID_THICK", color = COL_WHITE)))
  }), recursive = FALSE),
  # status colours on the value cells: NRR and LTV:CAC follow the Status column on Unit Economics,
  # runway follows the 'Runway warning below' input. CF cannot name another tab, hence INDIRECT.
  list(fmt_cond_formula(S, 9, 9, 6, 7, sprintf('=INDIRECT("\'Unit Economics\'!$G$%d")="On track"', U$nrr), font_color = COL_GREEN_TXT),
       fmt_cond_formula(S, 9, 9, 6, 7, sprintf('=INDIRECT("\'Unit Economics\'!$G$%d")="Watch"', U$nrr), font_color = COL_AMBER_TEXT),
       fmt_cond_formula(S, 9, 9, 12, 13, sprintf('=INDIRECT("\'Unit Economics\'!$G$%d")="On track"', U$ltvcac), font_color = COL_GREEN_TXT),
       fmt_cond_formula(S, 9, 9, 12, 13, sprintf('=INDIRECT("\'Unit Economics\'!$G$%d")="Watch"', U$ltvcac), font_color = COL_AMBER_TEXT),
       fmt_cond_formula(S, 9, 9, 10, 11, RUNWAY_LOW, font_color = COL_RED_TXT),
       fmt_cond_formula(S, 9, 9, 10, 11, sprintf("=NOT(%s)", sub("^=", "", RUNWAY_LOW)), font_color = COL_GREEN_TXT),
       # section bars
       fmt_merge(S, 13, 13, 2, 7), fmt_merge(S, 13, 13, 8, 13),
       fmt_cells(S, 13, 13, 2, 13, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
       fmt_borders(S, 13, 13, 8, 13, left = list(style = "SOLID_THICK", color = COL_WHITE)),
       fmt_merge(S, 32, 32, 2, 8), fmt_merge(S, 32, 32, 9, 13),
       fmt_cells(S, 32, 32, 2, 13, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
       fmt_borders(S, 32, 32, 9, 13, left = list(style = "SOLID_THICK", color = COL_WHITE)),
       # annual snapshot table
       fmt_merge(S, 33, 33, 9, 10),
       fmt_cells(S, 33, 33, 9, 13, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "RIGHT"),
       fmt_cells(S, 33, 33, 9, 10, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT")),
  unlist(lapply(seq_along(SNAP), function(i) {
    rw <- 33L + i; nf <- SNAP[[i]][[3]]
    list(fmt_merge(S, rw, rw, 9, 10),
         fmt_cells(S, rw, rw, 9, 10, font_size = 10, halign = "LEFT"),
         fmt_cells(S, rw, rw, 11, 12, font_size = 10, bold = TRUE, numfmt = nf, halign = "RIGHT"),
         fmt_cells(S, rw, rw, 13, 13, font_size = 10, font_color = COL_MUTED, numfmt = NF('+0%;-0%'), halign = "RIGHT"),
         ln(S, rw, rw, 9, 13))
  }), recursive = FALSE),
  unlist(lapply(seq_along(HOWTO), function(i) {
    rw <- 41L + i
    list(fmt_merge(S, rw, rw, 9, 13),
         fmt_cells(S, rw, rw, 9, 13, font_size = 10, bold = (i == 1L), font_color = if (i == 1L) COL_BRAND_DEEP else COL_INK,
            bg_color = COL_BRAND_SUBTLE, halign = "LEFT"))
  }), recursive = FALSE),
  # scenario comparison: one row per metric, three 3-column blocks (Base / Upside / Downside), selected one highlighted
  list(fmt_merge(S, SU$cmp, SU$cmp, 2, 13),
       fmt_cells(S, SU$cmp, SU$cmp, 2, 13, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
       fmt_merge(S, SU$cmp_hdr, SU$cmp_hdr, 2, 4),
       fmt_cells(S, SU$cmp_hdr, SU$cmp_hdr, 2, 13, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "CENTER"),
       fmt_cells(S, SU$cmp_hdr, SU$cmp_hdr, 2, 4, font_size = 10, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND_DEEP, halign = "LEFT")),
  lapply(CMP_COL, function(c0) fmt_merge(S, SU$cmp_hdr, SU$cmp_hdr, c0, c0 + 2L)),
  unlist(lapply(seq_along(CMP), function(i) {
    rw <- SU$cmp_first + i - 1L
    c(list(fmt_merge(S, rw, rw, 2, 4), fmt_cells(S, rw, rw, 2, 4, font_size = 10, halign = "LEFT")),
      lapply(CMP_COL, function(c0) fmt_merge(S, rw, rw, c0, c0 + 2L)),
      list(fmt_cells(S, rw, rw, 5, 13, font_size = 11, bold = TRUE, numfmt = CMP[[i]][[3]], halign = "CENTER"), ln(S, rw, rw, 2, 13)))
  }), recursive = FALSE),
  lapply(CMP_COL, function(c0) fmt_cond_formula(S, SU$cmp_first, cmp_last, c0, c0 + 2L,
                                                sprintf("=$%s$%d=$C$5", col_letter(c0), SU$cmp_hdr), bg_color = COL_BRAND_SUBTLE)),
  lapply(CMP_COL[-1L], function(c0) fmt_borders(S, SU$cmp_first, cmp_last, c0, c0 + 2L, left = list(style = "SOLID", color = COL_RULE))),
  list(fmt_cond_negative(S, SU$cmp_first, cmp_last, 5, 13, color = COL_NEGATIVE),
       fmt_cells(S, SU$cmp_note, SU$cmp_note, 2, 2, font_size = 9, italic = TRUE, font_color = COL_MUTED),
       fmt_merge(S, SU$about, SU$about, 2, 13),
       fmt_cells(S, SU$about, SU$about, 2, 13, font_size = 11, bold = TRUE, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
       fmt_cells(S, SU$about + 1L, SU$about + 6L, 2, 2, font_size = 10, font_color = COL_INK),
       fmt_cells(S, SU$about + 6L, SU$about + 6L, 2, 2, font_size = 10, italic = TRUE, font_color = COL_MUTED),
       fmt_cells(S, SU$about + 3L, SU$about + 3L, 2, 2, font_size = 10, font_color = hex_to_color("1155CC")),
       fmt_cells(S, SU$about + 5L, SU$about + 5L, 2, 2, font_size = 10, font_color = hex_to_color("1155CC")),
       fmt_protected_range(S, description = "Dashboard: formulas. Edit only the two yellow selectors",
                           unprotected_ranges = list(grid_range(S, 5, 5, 3, 3), grid_range(S, 5, 5, 7, 7)))))

# Send formatting, one batch per tab (a failing request then names its tab)
for (nm in list(c("asm", "fmt_asm"), c("fc", "fmt_fc"), c("br", "fmt_br"), c("co", "fmt_co"),
                c("ue", "fmt_ue"), c("sn", "fmt_sn"), c("ck", "fmt_ck"), c("sum", "fmt_sum"))) {
  message("[format] ", TAB[[nm[1]]])
  batch_format(ss, Filter(length, get(nm[2])), strict = TRUE)
}

# =============================================================================
# 3. CHARTS (after values exist; each reads its data tab and sits on Summary, Bridge or Cohorts)
# =============================================================================
wf <- function(anchor_row, anchor_col, size, on)       # `on` = tab the chart sits on; the data is on MRR Bridge
  fmt_chart_waterfall(sid[["br"]], "MRR bridge, $ per month",
                      domain_range = c(B$feed, B$feed + 5L, 2, 2), data_range = c(B$feed, B$feed + 5L, 3, 3),
                      positive_color = COL_POSITIVE, negative_color = COL_NEGATIVE,
                      subtotal_color = COL_BRAND_DEEP, connector_type = "DOTTED",
                      subtotal_indices = c(0L, 5L),            # Opening and Closing are totals
                      subtotal_label = "Total", data_labels = TRUE,
                      anchor = c(anchor_row, anchor_col), size = size, anchor_sheet_id = on, style = CHART_STYLE)
fcs <- sid[["fc"]]; sns <- sid[["sn"]]
dom <- c(r$f_month, r$f_month, 3, 3L + N_M)
rowr <- function(k) c(r[[k]], r[[k]], 3, 3L + N_M)
rows_sn <- function(row) c(row, row, 3, 3L + N_M)
# ARR by scenario: three thin lines, the selected scenario again in bold, and markers (with value labels) at months 12 and 24
arr_chart <- fmt_chart_basic(sns, "ARR by scenario, month end", "LINE", rows_sn(SE_F$date),
                             list(list(range = rows_sn(SE_F$base), color = COL_BRAND, line = list(width = 2)),
                                  list(range = rows_sn(SE_F$up), color = COL_POSITIVE, line = list(width = 2)),
                                  list(range = rows_sn(SE_F$down), color = COL_WARNING, line = list(width = 2)),
                                  list(range = rows_sn(SE_F$sel), color = COL_BRAND_DEEP, line = list(width = 5)),
                                  list(range = rows_sn(SE_F$mark), color = COL_BRAND_DEEP,
                                       line = list(type = "INVISIBLE", width = 0), point = list(shape = "CIRCLE", size = 9),
                                       label = list(type = "DATA", placement = "BELOW"))),
                             anchor = c(14, 8), size = c(554L, 352L), x_title = "Month", y_title = "ARR",
                             anchor_sheet_id = sid[["sum"]], style = CHART_STYLE)
mv_chart <- fmt_chart_basic(fcs, "MRR movements by month", "COLUMN", dom,
                            list(list(range = rowr("f_new"), color = COL_BRAND),
                                 list(range = rowr("f_exp"), color = COL_SOFT_B),
                                 list(range = rowr("f_con"), color = COL_WARNING),
                                 list(range = rowr("f_churn"), color = COL_NEGATIVE)),
                            stacked_type = "STACKED", anchor = c(33, 2), size = c(644L, 296L),
                            x_title = "Month", y_title = "MRR movement per month", anchor_sheet_id = sid[["sum"]],
                            style = CHART_STYLE)
batch_format(ss, list(wf(14, 2, c(554L, 352L), sid[["sum"]]),   # 554 px = the 6 x 92 px section bar plus the chart border
                      arr_chart, mv_chart), strict = TRUE)
# Cohort retention curves: feed rows on the Cohorts tab, the chart sits below them.
cr <- function(row) c(row, row, 5, 17)
co_chart <- fmt_chart_basic(sid[["co"]], "Retention curves: best, average and weakest cohort", "LINE", cr(CO$feed + 1L),
                            list(list(range = cr(CO$feed + 2L), color = COL_POSITIVE),
                                 list(range = cr(CO$feed + 3L), color = COL_BRAND, line = list(width = 4)),
                                 list(range = cr(CO$feed + 4L), color = COL_NEGATIVE)),
                            anchor = c(CO$chart, 2), size = c(760L, 300L),
                            x_title = "Months since signup", y_title = "Customers still active",
                            y_min = 0, y_max = 1,                              # 0-100% fits any quality input (a low one can fall under 50%)
                            style = CHART_STYLE)
# The Bridge waterfall is 560 px wide: at 550+ the category labels stay horizontal (at 520 they slanted and clipped "MRR").
batch_format(ss, list(wf(B$chart, B$chart_col, c(560L, 340L), sid[["br"]]), co_chart), strict = TRUE)

# Rich-text links last: the cells are pre-coloured blue in the Summary batch, and link_cells_req() keeps that colour.
batch_format(ss, list(
  link_cells_req(sid[["sum"]], SU$about + 3L, 2, REPO_URL, REPO_URL),
  link_cells_req(sid[["sum"]], SU$about + 5L, 2, DOCS_URL, DOCS_URL)), strict = TRUE)

# =============================================================================
# 4. POST-BUILD QA (cells; the visual pass is run separately with visual_qa())
# =============================================================================
Sys.sleep(3)
meta <- gargle::response_process(googlesheets4::request_make(googlesheets4::request_generate("sheets.spreadsheets.get",
  params = list(spreadsheetId = ss_id, fields = "sheets(properties(title),charts(chartId))"))))
n_ch <- vapply(meta$sheets, function(s) length(s$charts), integer(1)); names(n_ch) <- vapply(meta$sheets, function(s) s$properties$title, "")
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
status <- read_values(ss, "Checks!D4")[[1]][1, 1]
message("[QA] no error values in any tab; Checks status = ", status)
stopifnot(identical(status, "Model ties: OK"))

cat("\nSheet id : ", ss_id, "\nSheet URL: https://docs.google.com/spreadsheets/d/", ss_id,
    "\nRebuild  : SHEET_ID=", ss_id, " GS_SKILL_DIR=", SKILL, " Rscript examples/showcases/saas-model.R\n", sep = "")
