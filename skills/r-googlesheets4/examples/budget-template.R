# budget-template.R — multi-dept loop (one file per department) using brand.R
#
# Styled with the default "Ledger" look, which loads with gs_helpers.R. brand.R
# is the one place to change the accent and font for every department file; with
# its default values it changes nothing. Run end-to-end with stub data; replace
# the placeholder data sources with your real CSVs.

USER_EMAIL <- NULL  # NULL = account saved by gs_setup.sh; or "you@example.com"

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
source(file.path(SKILL, "scripts/gs_helpers.R"))
source(file.path(SKILL, "scripts/gs_buffer.R"))
source(file.path(SKILL, "scripts/gs_qa.R"))
source(file.path(SKILL, "scripts/gs_formulas.R"))
source(file.path(SKILL, "scripts/brand.R"))   # optional: accent + font swap

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

  # Buffer cell writes: title block (rows 2-4), then the executive summary
  write_cell(ss, dept, 2, 2, sprintf("%s, FY2026 budget", dept))
  write_cell(ss, dept, 3, 2, sprintf('="Total cost is "&TEXT(C9,"$#,##0")&"; people are "&TEXT(%s,"0%%")&" of it."',
                                    fraw(f_safe_div("C7", "C9"))))   # the finding: a live formula
  write_cell(ss, dept, 4, 2, paste("Department summary · stub data · USD · built", safe_locale_date(Sys.Date())))

  write_cell(ss, dept, 6, 2, "Executive summary")
  write_cell(ss, dept, 7, 2, "Total people")
  write_cell(ss, dept, 7, 3, '=SUM(People!C:C)')
  write_cell(ss, dept, 8, 2, "Total OPEX")
  write_cell(ss, dept, 8, 3, '=SUM(OPEX!D:D)')
  write_cell(ss, dept, 9, 2, "Total cost")
  write_cell(ss, dept, 9, 3, "=C7+C8")
  write_cell(ss, dept, 11, 2, "Source: People and OPEX tabs; green figures come from them.")

  flush_writes(ss)
  Sys.sleep(2)

  # Composable formatting — global default first, section overrides second.
  # Every helper returns a request list, so they combine with c().
  global_fmt <- c(
    list(do.call(fmt_theme_colors, THEME_DEFAULT)),     # font + chart colours (follows brand.R)
    fmt_tab_base(sid, 20, 4, "dashboard", widths = c(280, 130))
  )

  summary_fmt <- c(
    fmt_section(sid, 6, 2, 3, header = FALSE),          # heading over an ink rule
    fmt_table_body(sid, 7, 9, 2, 3, numeric_cols = 3, numfmt = NUMFMT_CURRENCY,
                   total_rows = 9),                     # Total cost: ink rule above, double below
    list(fmt_cells(sid, 7, 8, 3, 3, font_color = COL_LINK_FG),   # finance colour code: from another tab
         apply_style(sid, 11, 11, 2, 2, STYLE_NOTE),
         fmt_row_height(sid, 10, 10, 8L))
  )

  batch_format(ss, c(global_fmt, summary_fmt), strict = TRUE)

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
