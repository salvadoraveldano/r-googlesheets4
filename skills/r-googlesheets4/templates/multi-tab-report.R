# multi-tab-report.R — Cover + multiple data tabs + cross-sheet aggregation
#
# A complete styled report: Cover tab with a KPI strip + 3 raw data tabs, in
# the default "Ledger" look. Demonstrates the 2-call pattern (flush +
# batch_format) per tab.

USER_EMAIL <- NULL  # NULL = account saved by gs_setup.sh; or "you@example.com"

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
source(file.path(SKILL, "scripts/gs_helpers.R"))
source(file.path(SKILL, "scripts/gs_buffer.R"))
source(file.path(SKILL, "scripts/gs_qa.R"))
source(file.path(SKILL, "scripts/gs_formulas.R"))   # f_safe_div, fraw

library(tibble)

# ── Connect ── uses the login saved by scripts/gs_setup.sh; never opens a browser
gs_connect(USER_EMAIL)

# ── Demo data ──
people_df <- tibble(
  source = c("Tech", "Sales", "Ops"),
  alloc  = c("Tech", "Sales", "Ops"),
  cost   = c(120000, 80000, 60000)
)
opex_df <- tibble(
  source   = c("Tech", "Sales", "Ops"),
  category = c("SaaS", "Travel", "Office"),
  amount   = c(50000, 25000, 15000)
)
revenue_df <- tibble(
  customer = c("Acme", "Beta", "Gamma"),
  source   = c("Tech", "Sales", "Tech"),
  amount   = c(200000, 150000, 90000)
)

# ── Create the workbook ──
ss <- gs_open_or_create("Multi-Tab Report Demo", c("Cover", "People", "OPEX", "Revenue"))

# Bulk write data tabs
sheet_write(people_df,  ss, sheet = "People")
sheet_write(opex_df,    ss, sheet = "OPEX")
sheet_write(revenue_df, ss, sheet = "Revenue")

# ── Cover tab — KPIs and cross-sheet formulas ──
cover_id  <- get_sheet_id(ss, "Cover")

# Title block (rows 2-4), then a KPI strip: labels row 6, values row 7, a
# muted sub-value row 8. The lead figure (Net) answers the tab's question.
write_cell(ss, "Cover", 2, 2, "FY2026 summary")
share <- function(a, b) fraw(f_safe_div(a, b))    # a/b, "" when b is 0
write_cell(ss, "Cover", 3, 2, sprintf('="Net is "&TEXT(B7,"$#,##0;($#,##0)")&", a "&TEXT(%s,"0.0%%")&" margin on "&TEXT(C7,"$#,##0")&" of revenue."',
                                      share("B7", "C7")))   # the finding: a live formula, never stale
write_cell(ss, "Cover", 4, 2, paste("Demo data · from the People, OPEX and Revenue tabs · USD · built", safe_locale_date()))

kpi <- list(   # column, label, value (cross-sheet formula), sub-value
  list(2, "Net",         "=C7-D7-E7",          sprintf('=TEXT(%s,"0.0%%")&" margin"', share("B7", "C7"))),
  list(3, "Revenue",     "=SUM(Revenue!C:C)",  '=COUNTA(Revenue!A2:A)&" customers"'),
  list(4, "People cost", "=SUM(People!C:C)",   sprintf('=TEXT(%s,"0%%")&" of revenue"', share("D7", "C7"))),
  list(5, "OPEX",        "=SUM(OPEX!C:C)",     sprintf('=TEXT(%s,"0%%")&" of revenue"', share("E7", "C7"))))
for (k in kpi) for (i in 1:3) write_cell(ss, "Cover", 5 + i, k[[1]], k[[i + 1]])
write_cell(ss, "Cover", 10, 2, "Source: SUM over each data tab, so the Cover follows any row you add.")

flush_writes(ss)
Sys.sleep(2)

# ── Format Cover tab ──
# fmt_tab_base: body style, gridlines off, 16 px gutters, title/finding/meta rows
batch_format(ss, c(
  list(do.call(fmt_theme_colors, THEME_DEFAULT)),     # font + chart colours, once per file
  fmt_tab_base(cover_id, 12, 6, "dashboard", widths = c(224, 112, 112, 112)),
  fmt_kpi_strip(cover_id, 6, 2:5, lead = 2, good = "none", value_numfmt = NUMFMT_CURRENCY, delta_numfmt = NULL),
  list(fmt_row_height(cover_id, 5, 5, 12L), fmt_row_height(cover_id, 9, 9, 8L),
       apply_style(cover_id, 10, 10, 2, 2, STYLE_NOTE),
       fmt_cond_negative(cover_id, 7, 7, 2, 2))      # red if Net < 0 (output tabs only)
), strict = TRUE)

# ── Format raw data tabs: gridlines on, row 1 frozen, a grey header over a rule ──
for (tab in c("People", "OPEX", "Revenue")) {
  tab_id <- get_sheet_id(ss, tab)
  batch_format(ss, c(
    fmt_tab_base(tab_id, 4, 3, "data"),
    fmt_section(tab_id, 1, 1, 3, numeric_cols = 3, heading = FALSE),
    list(fmt_cells(tab_id, 1, 1, 1, 3, bg_color = COL_WHITE),   # drop sheet_write()'s grey header fill
         fmt_cells(tab_id, 2, 4, 3, 3, numfmt = NUMFMT_CURRENCY),
         fmt_col_width(tab_id, 1, 3, 112L))
  ), strict = TRUE)
  Sys.sleep(1)
}

# ── Reorder so Cover is first ──
sheet_relocate(ss, sheet = "Cover", .before = 1)

# ── QA ──
audit_chart_sources(as.character(ss), cover_id)

cat("Sheet:", gs4_browse(ss), "\n")
