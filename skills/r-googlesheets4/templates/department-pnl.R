# department-pnl.R — Department P&L tab with raw-data tabs and SUMIFS
#
# Pattern: per-dept workbook with filtered raw-data tabs. Same column layout
# as the consolidated workbook, so SUMIFS formulas work unchanged.
#
# Edit the parameters at the top, then run.

# ── Parameters ──
DEPT       <- "Sales"
USER_EMAIL <- NULL  # NULL = account saved by gs_setup.sh; or "you@example.com"

# Data source paths — point at your real files
PEOPLE_CSV  <- "data/people_expense.csv"
OPEX_CSV    <- "data/opex_data.csv"
REVENUE_CSV <- "data/revenue.csv"

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
source(file.path(SKILL, "scripts/gs_helpers.R"))
source(file.path(SKILL, "scripts/gs_buffer.R"))
source(file.path(SKILL, "scripts/gs_qa.R"))
source(file.path(SKILL, "scripts/gs_formulas.R"))

library(tibble)
library(dplyr)
library(readr)

# ── Connect ── uses the login saved by scripts/gs_setup.sh; never opens a browser
gs_connect(USER_EMAIL)

# ── Load + filter ──
people_df  <- read_csv(PEOPLE_CSV,  show_col_types = FALSE)
opex_df    <- read_csv(OPEX_CSV,    show_col_types = FALSE)
revenue_df <- read_csv(REVENUE_CSV, show_col_types = FALSE)

dept_people  <- people_df  %>% filter(source == DEPT | alloc == DEPT)
dept_opex    <- opex_df    %>% filter(origin == DEPT | target == DEPT)
dept_revenue <- revenue_df %>% filter(department == DEPT)

# ── Create the spreadsheet ──
tab_names <- c(DEPT, "People", "OPEX", "Revenue")
ss <- gs_open_or_create(sprintf("%s — FY2026 Summary", DEPT), tab_names)

# Bulk write raw-data tabs
sheet_write(dept_people,  ss, sheet = "People")
sheet_write(dept_opex,    ss, sheet = "OPEX")
sheet_write(dept_revenue, ss, sheet = "Revenue")

sid <- get_sheet_id(ss, DEPT)
sn  <- DEPT

# ══════════════════════════════════════════════════════════════════════════
# STEP 1: Buffer all cell writes
# ══════════════════════════════════════════════════════════════════════════

# R1: dept name (anchor for $C$1 references)
write_cell(ss, sn, 1, 3, DEPT)
write_cell(ss, sn, 2, 3, sprintf('=$C$1&" — FY2026 Budget Summary"'))
write_cell(ss, sn, 3, 3, "Department Summary")
write_cell(ss, sn, 3, 6, safe_locale_date())

# R4: exec summary header (collected for batch formatting later)
all_fmt <- list()
all_fmt <- c(all_fmt, write_section_header(ss, sn, sid, 4, "EXECUTIVE SUMMARY",
                                           bg_color = hex_to_color("2457C5")))

# R5-R8: exec summary metrics
write_cell(ss, sn, 5, 3, "  Gross Profit")
write_cell(ss, sn, 5, 6, '=SUMIFS(Revenue!D:D,Revenue!A:A,$C$1,Revenue!C:C,"Net revenue")')
write_cell(ss, sn, 6, 3, "  Total OPEX")
write_cell(ss, sn, 6, 6, '=SUMIFS(People!C:C,People!B:B,$C$1)+SUMIFS(OPEX!M:M,OPEX!C:C,$C$1)')
write_cell(ss, sn, 7, 3, "  Net Income")
write_cell(ss, sn, 7, 6, "=F5-F6")
write_cell(ss, sn, 8, 3, "  Net Margin %")
write_cell(ss, sn, 8, 6, f_safe_div("F7", "F5"))

# R10: P&L section header
all_fmt <- c(all_fmt, write_section_header(ss, sn, sid, 10, "P&L",
                                           bg_color = hex_to_color("2457C5")))

# … add more rows here as needed (revenue, OPEX, allocation breakdowns) …

# ══════════════════════════════════════════════════════════════════════════
# STEP 2: Flush all writes
# ══════════════════════════════════════════════════════════════════════════
flush_writes(ss)
Sys.sleep(3)   # let backend commit before formatting

# ══════════════════════════════════════════════════════════════════════════
# STEP 3: Composable formatting sub-functions
# ══════════════════════════════════════════════════════════════════════════
last_row <- 80L

fmt_global <- function(sid, last_row) {
  c(
    list(
      fmt_gridlines(sid, show = FALSE),
      fmt_freeze(sid, rows = 4),
      fmt_col_width(sid, 1, 1, 20),
      fmt_col_width(sid, 3, 3, 310),
      fmt_col_width(sid, 4, 6, 150),
      fmt_col_width(sid, 7, 8, 110),
      apply_style(sid, 1, last_row, 1, 8, STYLE_BODY)
    )
  )
}

fmt_header <- function(sid) {
  list(
    fmt_merge(sid, 2, 2, 3, 8),
    apply_style(sid, 2, 2, 3, 8, STYLE_TITLE),
    apply_style(sid, 3, 3, 3, 3, STYLE_SUBTITLE),
    apply_style(sid, 3, 3, 6, 6, STYLE_SUBTITLE, halign = "RIGHT"),
    fmt_cells(sid, 5, 7, 6, 6,
              numfmt_type    = NUMFMT_CURRENCY_K$type,
              numfmt_pattern = NUMFMT_CURRENCY_K$pattern),
    apply_style(sid, 8, 8, 6, 6, STYLE_PCT_ANNOTATION,
                numfmt_type    = NUMFMT_PCT$type,
                numfmt_pattern = NUMFMT_PCT$pattern)
  )
}

fmt_pnl_section <- function(sid) {
  list(
    fmt_borders(sid, 10, 35, 3, 8,
                top    = list(style = "DOUBLE", color = hex_to_color("2457C5")),
                bottom = list(style = "DOUBLE", color = hex_to_color("2457C5")),
                left   = list(style = "DOUBLE", color = hex_to_color("2457C5")),
                right  = list(style = "DOUBLE", color = hex_to_color("2457C5"))),
    fmt_cells(sid, 11, 35, 4, 6,
              numfmt_type    = NUMFMT_CURRENCY$type,
              numfmt_pattern = NUMFMT_CURRENCY$pattern)
  )
}

# ══════════════════════════════════════════════════════════════════════════
# STEP 4: Assemble + send in ONE batch_format() call
# ══════════════════════════════════════════════════════════════════════════
all_fmt <- c(
  fmt_global(sid, last_row),
  all_fmt,
  fmt_header(sid),
  fmt_pnl_section(sid)
)
batch_format(ss, all_fmt)

# ══════════════════════════════════════════════════════════════════════════
# STEP 5: Post-build QA
# ══════════════════════════════════════════════════════════════════════════
ss_id <- as.character(ss)
audit_chart_sources(ss_id, sid)
stopifnot(first_visible_col(ss_id, sid) <= 1L)
cat("[QA] post-build checks passed\n")

# ── Done ──
cat("Sheet URL:", gs4_browse(ss), "\n")
