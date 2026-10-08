# budget-template.R — branded multi-dept loop using brand.R
#
# Demonstrates layering brand presets on top of generic styles. Run end-to-end
# with stub data; replace the placeholder data sources with your real CSVs.

USER_EMAIL <- NULL  # NULL = account saved by gs_setup.sh; or "you@example.com"

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
source(file.path(SKILL, "scripts/gs_helpers.R"))
source(file.path(SKILL, "scripts/gs_buffer.R"))
source(file.path(SKILL, "scripts/gs_qa.R"))
source(file.path(SKILL, "scripts/gs_formulas.R"))
source(file.path(SKILL, "scripts/brand.R"))

library(tibble)
library(dplyr)

# ── Connect ── uses the login saved by scripts/gs_setup.sh; never opens a browser
gs_connect(USER_EMAIL)

# ── Stub data — replace with read_csv() of your real files ──
people_df <- tibble(
  source = c("Technology", "Sales", "Operations"),
  alloc  = c("Technology", "Sales", "Operations"),
  cost   = c(120000, 80000, 60000)
)

opex_df <- tibble(
  origin   = c("Technology", "Sales", "Operations"),
  target   = c("Technology", "Sales", "Operations"),
  category = c("SaaS", "Travel", "Office"),
  amount   = c(50000, 25000, 15000)
)

# ── Sub-loop: build one department's tab ──
build_dept <- function(dept) {
  cat(sprintf("Building %s...\n", dept))

  # Filter raw data for this dept (per the per-dept workbook architecture)
  d_people <- people_df %>% filter(source == dept | alloc == dept)
  d_opex   <- opex_df   %>% filter(origin == dept | target == dept)

  # Create the spreadsheet — 3 tabs: dept summary + two raw-data tabs
  tabs <- c(dept, "People", "OPEX")
  # One file per department: leave SHEET_ID unset for this loop, otherwise the second
  # department hits the title guard (id = "" always creates a new file).
  ss <- gs_open_or_create(sprintf("%s — FY2026 Summary", dept), tabs, id = "")
  sheet_write(d_people, ss, sheet = "People")
  sheet_write(d_opex,   ss, sheet = "OPEX")

  sid <- get_sheet_id(ss, dept)

  # Buffer cell writes
  write_cell(ss, dept, 1, 3, dept)
  write_cell(ss, dept, 2, 3, sprintf('=$C$1&" — FY2026 Budget Summary"'))
  write_cell(ss, dept, 3, 3, "Department Summary")
  write_cell(ss, dept, 3, 6, safe_locale_date(Sys.Date()))

  # Section headers via brand helper
  all_fmt <- list()
  all_fmt <- c(all_fmt,
               write_section_header_brand(ss, dept, sid, 4, "EXECUTIVE SUMMARY"))

  # Exec summary metrics
  write_cell(ss, dept, 5, 3, "  Total People")
  write_cell(ss, dept, 5, 6, '=SUM(People!C:C)')
  write_cell(ss, dept, 6, 3, "  Total OPEX")
  write_cell(ss, dept, 6, 6, '=SUM(OPEX!D:D)')
  write_cell(ss, dept, 7, 3, "  Total Cost")
  write_cell(ss, dept, 7, 6, "=F5+F6")

  flush_writes(ss)
  Sys.sleep(2)

  # Composable formatting — global default first, section overrides second
  global_fmt <- c(
    list(
      fmt_gridlines(sid, show = FALSE),
      fmt_freeze(sid, rows = 4),
      fmt_col_width(sid, 1, 1, 20),
      fmt_col_width(sid, 3, 3, 280),
      fmt_col_width(sid, 4, 6, 130),
      apply_style(sid, 1, 50, 1, 8, STYLE_BODY)
    )
  )

  header_fmt <- list(
    fmt_merge(sid, 2, 2, 3, 6),
    apply_style(sid, 2, 2, 3, 6, STYLE_BRAND_TITLE),
    apply_style(sid, 3, 3, 3, 3, STYLE_SUBTITLE),
    fmt_cells(sid, 5, 7, 6, 6,
              numfmt_type = NUMFMT_CURRENCY$type,
              numfmt_pattern = NUMFMT_CURRENCY$pattern)
  )

  emphasis_fmt <- list(
    apply_style(sid, 7, 7, 3, 6, STYLE_BRAND_SUBTOTAL,
                numfmt_type = NUMFMT_CURRENCY$type,
                numfmt_pattern = NUMFMT_CURRENCY$pattern)
  )

  batch_format(ss, c(global_fmt, all_fmt, header_fmt, emphasis_fmt))

  # Post-build QA
  audit_chart_sources(as.character(ss), sid)

  cat(sprintf("  → %s\n", as.character(ss)))
  invisible(ss)
}

# ── Loop over the 3 stub depts (or your own department list) ──
for (dept in c("Technology", "Sales", "Operations")) {
  build_dept(dept)
  Sys.sleep(3)   # smooth out the loop, stay under quota
}
