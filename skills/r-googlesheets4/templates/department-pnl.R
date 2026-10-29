# department-pnl.R — Department P&L tab with raw-data tabs and SUMIFS
#
# Pattern: per-dept workbook with filtered raw-data tabs. Same column layout
# as the consolidated workbook, so SUMIFS formulas work unchanged. Styled with
# the default "Ledger" look (references/design-principles.md).
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

# R2: dept name as the tab title, and the anchor every SUMIFS reads ($B$2)
write_cell(ss, sn, 2, 2, DEPT)
write_cell(ss, sn, 3, 2, '=$B$2&" net income is "&TEXT(C9,"$#,##0,""K"";($#,##0,""K"")")&", a "&TEXT(C10,"0.0%")&" margin on gross profit."')   # live finding
write_cell(ss, sn, 4, 2, paste("FY2026 budget summary · from the People, OPEX and Revenue tabs · USD · built", safe_locale_date()))

# R6-R10: executive summary. Green figures pull from another tab (finance colour code).
write_cell(ss, sn, 6, 2, "Executive summary")
write_cell(ss, sn, 7, 2, "Gross profit")
write_cell(ss, sn, 7, 3, '=SUMIFS(Revenue!D:D,Revenue!A:A,$B$2,Revenue!C:C,"Net revenue")')
write_cell(ss, sn, 8, 2, "Total OPEX")
write_cell(ss, sn, 8, 3, '=SUMIFS(People!C:C,People!B:B,$B$2)+SUMIFS(OPEX!M:M,OPEX!C:C,$B$2)')
write_cell(ss, sn, 9, 2, "Net income")
write_cell(ss, sn, 9, 3, "=C7-C8")
write_cell(ss, sn, 10, 2, "Net margin")
write_cell(ss, sn, 10, 3, f_safe_div("C9", "C7"))

# R12-R13: P&L section heading + column headers; the body starts at R14
write_cell(ss, sn, 12, 2, "P&L")
write_block(ss, sn, 13, 2, rbind(c("Line item", "Budget", "Actual", "Variance")))
write_cell(ss, sn, 14, 2, "Add revenue, OPEX and allocation rows here.")
PNL_FIRST <- 14L; PNL_LAST <- 17L   # widen as you add rows

# … add more rows here as needed (revenue, OPEX, allocation breakdowns) …

# ══════════════════════════════════════════════════════════════════════════
# STEP 2: Flush all writes
# ══════════════════════════════════════════════════════════════════════════
flush_writes(ss)
Sys.sleep(3)   # let backend commit before formatting

# ══════════════════════════════════════════════════════════════════════════
# STEP 3: Composable formatting sub-functions (each returns a request list)
# ══════════════════════════════════════════════════════════════════════════
last_row <- 30L

# Theme (font, chart colours) once per file, then the tab base: body style,
# gridlines off, 16 px gutters, title / finding / meta rows. No freeze on a summary.
fmt_global <- function(sid, last_row) {
  c(list(do.call(fmt_theme_colors, THEME_DEFAULT)),
    fmt_tab_base(sid, last_row, 6, "dashboard", widths = c(240, 112, 112, 112)))
}

fmt_summary <- function(sid) {
  c(fmt_section(sid, 6, 2, 5, header = FALSE),                  # heading over an ink rule
    fmt_table_body(sid, 7, 9, 2, 5, numeric_cols = 3, numfmt = NUMFMT_CURRENCY_K,
                   total_rows = 9),                             # Net income: ink rule above, double below
    list(fmt_cells(sid, 7, 8, 3, 3, font_color = COL_LINK_FG),  # from another tab
         apply_style(sid, 10, 10, 2, 3, STYLE_NOTE),
         fmt_cells(sid, 10, 10, 3, 3, numfmt = NUMFMT_PCT, halign = "RIGHT"),
         fmt_row_height(sid, 11, 11, 20L)))
}

fmt_pnl_section <- function(sid) {
  c(fmt_section(sid, 12, 2, 5, numeric_cols = 3:5),             # heading + header row (R13)
    fmt_table_body(sid, PNL_FIRST, PNL_LAST, 2, 5, numeric_cols = 3:5, numfmt = NUMFMT_CURRENCY),
    list(apply_style(sid, PNL_FIRST, PNL_FIRST, 2, 2, STYLE_NOTE)))
}

# ══════════════════════════════════════════════════════════════════════════
# STEP 4: Assemble + send in ONE batch_format() call
# ══════════════════════════════════════════════════════════════════════════
all_fmt <- c(
  fmt_global(sid, last_row),
  fmt_summary(sid),
  fmt_pnl_section(sid)
)
batch_format(ss, all_fmt, strict = TRUE)

# ══════════════════════════════════════════════════════════════════════════
# STEP 5: Post-build QA
# ══════════════════════════════════════════════════════════════════════════
ss_id <- as.character(ss)
audit_chart_sources(ss_id, sid)
stopifnot(first_visible_col(ss_id, sid) <= 1L)
cat("[QA] post-build checks passed\n")

# ── Done ──
cat("Sheet URL:", gs4_browse(ss), "\n")
