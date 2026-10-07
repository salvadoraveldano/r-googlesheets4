# multi-tab-report.R — Cover + multiple data tabs + cross-sheet aggregation
#
# A complete styled report: Cover tab with KPIs + 3 raw data tabs.
# Demonstrates the 2-call pattern (flush + batch_format) per tab.

USER_EMAIL <- NULL  # NULL = account saved by gs_setup.sh; or "you@example.com"

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
source(file.path(SKILL, "scripts/gs_helpers.R"))
source(file.path(SKILL, "scripts/gs_buffer.R"))
source(file.path(SKILL, "scripts/gs_qa.R"))
source(file.path(SKILL, "scripts/gs_modern.R"))  # fmt_auto_resize_cols

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
people_id <- get_sheet_id(ss, "People")
opex_id   <- get_sheet_id(ss, "OPEX")

write_cell(ss, "Cover", 1, 1, "FY2026 Summary")
write_cell(ss, "Cover", 2, 1, safe_locale_date())

write_cell(ss, "Cover", 4, 1, "Total People Cost")
write_cell(ss, "Cover", 4, 2, "=SUM(People!C:C)")
write_cell(ss, "Cover", 5, 1, "Total OPEX")
write_cell(ss, "Cover", 5, 2, "=SUM(OPEX!C:C)")
write_cell(ss, "Cover", 6, 1, "Total Revenue")
write_cell(ss, "Cover", 6, 2, "=SUM(Revenue!C:C)")
write_cell(ss, "Cover", 7, 1, "Net")
write_cell(ss, "Cover", 7, 2, "=B6-B4-B5")

flush_writes(ss)
Sys.sleep(2)

# ── Format Cover tab ──
batch_format(ss, list(
  fmt_gridlines(cover_id, show = FALSE),
  fmt_freeze(cover_id, rows = 2),
  fmt_tab_color(cover_id, hex_to_color("2457C5")),
  fmt_col_width(cover_id, 1, 1, 280),
  fmt_col_width(cover_id, 2, 2, 180),

  # Title
  apply_style(cover_id, 1, 1, 1, 2, STYLE_TITLE),
  apply_style(cover_id, 2, 2, 1, 1, STYLE_SUBTITLE),

  # KPI labels + values
  apply_style(cover_id, 4, 7, 1, 1, STYLE_BODY, font_size = 12),
  fmt_cells(cover_id, 4, 7, 2, 2,
            font_family = "Arial", font_size = 12, bold = TRUE,
            numfmt_type    = NUMFMT_CURRENCY$type,
            numfmt_pattern = NUMFMT_CURRENCY$pattern,
            halign = "RIGHT"),

  # Net row gets emphasis
  apply_style(cover_id, 7, 7, 1, 2, STYLE_NET_INCOME,
              numfmt_type    = NUMFMT_CURRENCY$type,
              numfmt_pattern = NUMFMT_CURRENCY$pattern),

  # Conditional: red if Net < 0
  fmt_cond_negative(cover_id, 7, 7, 2, 2)
))

# ── Format raw data tabs ──
for (tab in c("People", "OPEX", "Revenue")) {
  tab_id <- get_sheet_id(ss, tab)
  batch_format(ss, list(
    fmt_freeze(tab_id, rows = 1),
    fmt_cells(tab_id, 1, 1, 1, 5,
              font_family = "Arial", bold = TRUE, font_size = 10,
              bg_color = COL_BLUE_LIGHT,
              halign = "CENTER"),
    fmt_auto_resize_cols(tab_id, 1, 5)
  ))
  Sys.sleep(1)
}

# ── Reorder so Cover is first ──
sheet_relocate(ss, sheet = "Cover", .before = 1)

# ── QA ──
audit_chart_sources(as.character(ss), cover_id)

cat("Sheet:", gs4_browse(ss), "\n")
