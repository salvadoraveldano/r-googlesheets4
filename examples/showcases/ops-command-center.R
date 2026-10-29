# =============================================================================
# ops-command-center.R - "Ops Command Center - Sample Data" showcase sheet
# =============================================================================
# Builds: a five-tab project / ops dashboard in Google Sheets from synthetic data,
#         styled with the skill's default "Ledger" design system.
#   Command Center  owner picker, live finding line, KPI strip, status and workstream 100%/stacked bars,
#                   burn-down (planned vs actual), top-5 "needs attention" table
#   Tasks           45 tasks, dropdowns, filter, saved views, slicer, sparkline progress bars,
#                   formula columns (days left, overdue, risk score, health) ready down to row 120
#   Timeline        weekly Gantt grid drawn by conditional formatting from formulas
#   Workload        owner x status counts and hours, load bars, a heatmap, capacity inputs
#   Lists           the fixed "as of" date, risk-score weights, dropdown sources, chart data
#
# First run (creates your own copy and prints its id; needs the saved login from gs_setup.sh):
#   GS_SKILL_DIR=<repo>/skills/r-googlesheets4 Rscript examples/showcases/ops-command-center.R
# Rerun (rebuilds that same file in place; needs no model; run from the repo root):
#   SHEET_ID=<id> GS_SKILL_DIR=<repo>/skills/r-googlesheets4 Rscript examples/showcases/ops-command-center.R
#   Safety: a rerun clears the five tabs of that file, so gs_open_or_create() first checks that its title is exactly SHEET_TITLE
#   (or that it already has all five tabs, as a copy of the sample does) and that its locale is en_US, and stops otherwise.
# Optional: QA_DIR=<folder> also exports every tab as PDF/PNG pages for a visual check.
# At the end the script reads the live sheet back and stops if any formula disagrees with the R reference.
#
# Reads: nothing external. All data is generated here with set.seed().
# Access level: the default "sheets" level (spreadsheets only). No Drive access,
#   no sharing, no installs. Sharing the sheet is a separate, manual step.
#
# Built with the r-googlesheets4 skill (https://github.com/salvadoraveldano/r-googlesheets4),
# built on googlesheets4 by Jennifer Bryan and Posit.
# =============================================================================

# ── Parameters ───────────────────────────────────────────────────────────────
SHEET_TITLE <- "Ops Command Center - Sample Data"
USER_EMAIL  <- NULL                      # NULL = account saved by gs_setup.sh
SEED        <- 5L
ASOF        <- as.Date("2026-09-28")     # fixed "today" (a Monday): reproducible; see Lists!B5
START       <- as.Date("2026-08-03")     # Monday of week 1 (Timeline and burn-down start)
N_WEEKS     <- 16L                       # weeks drawn on the Timeline
RISK_THRESHOLD <- 30L                    # open task with risk score >= this is "At risk"
RISK_W      <- c(prio = 5, gap = 60, over = 20, blocked = 10)   # risk score weights; written to Lists as inputs
OVERLOAD_WEEKS <- 4L                     # more weeks of work than this turns red on the Workload tab (an input on Lists)
LOAD_BAR_WEEKS <- 8L                     # weeks of work that fill the Workload load bar (an input on Lists)
REPO_URL    <- "https://github.com/salvadoraveldano/r-googlesheets4"
GS4_URL     <- "https://googlesheets4.tidyverse.org"
QA_DIR      <- Sys.getenv("QA_DIR", "")  # set to a folder to also export PDF/PNG pages

OWNERS      <- c("Ava", "Ben", "Chloe", "Diego", "Elena", "Farid", "Grace")
CAPACITY    <- c(32, 36, 40, 24, 40, 32, 36)       # hours per week per owner (inputs)
STATUSES    <- c("Not started", "In progress", "Blocked", "Done")
PRIORITIES  <- c("P0", "P1", "P2", "P3")
PRIO_W      <- c(4, 3, 2, 1)
ALL_LABEL   <- "All people"

TAB_CC <- "Command Center"; TAB_TASKS <- "Tasks"; TAB_TL <- "Timeline"
TAB_WL <- "Workload";       TAB_LISTS <- "Lists"
TABS   <- c(TAB_CC, TAB_TASKS, TAB_TL, TAB_WL, TAB_LISTS)

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
if (!file.exists(file.path(SKILL, "scripts", "gs_helpers.R")))
  stop("Set GS_SKILL_DIR to the skill directory (skills/r-googlesheets4 in the repo); no scripts/gs_helpers.R in '", SKILL, "'.", call. = FALSE)
for (f in c("gs_helpers.R", "gs_buffer.R", "gs_qa.R", "gs_formulas.R", "gs_charts.R",
            "gs_modern.R", "brand.R", "gs_visual_qa.R"))
  source(file.path(SKILL, "scripts", f))

# ── Synthetic data (pure R, no API) ──────────────────────────────────────────
set.seed(SEED)
task_names <- list(
  "Platform"         = c("Set up staging environment", "Migrate job scheduler", "Refactor config loader",
                         "Add retry logic to sync", "Upgrade base images", "Tune database indexes",
                         "Automate nightly backups", "Document service limits", "Remove legacy endpoints"),
  "Onboarding"       = c("Draft welcome checklist", "Build sign-up walkthrough", "Record setup tutorial",
                         "Pilot with first cohort", "Collect pilot feedback", "Simplify account form",
                         "Translate help articles", "Write FAQ for new users", "Review email templates"),
  "Data & Reporting" = c("Define core metrics", "Build weekly summary view", "Validate source tables",
                         "Add data quality alerts", "Backfill history", "Design executive dashboard",
                         "Document metric definitions", "Schedule report refresh", "Audit report permissions"),
  "Compliance"       = c("Map data flows", "Review access roles", "Update retention policy",
                         "Run vendor questionnaire", "Prepare audit evidence", "Test incident runbook",
                         "Train team on policy", "Close open findings", "Draft risk register"),
  "Launch"           = c("Finalize release plan", "Run load test", "Prepare launch announcement",
                         "Brief support team", "Set up status page", "Dry-run rollout",
                         "Plan rollback steps", "Collect go/no-go sign-offs", "Schedule post-launch review"))
WORKSTREAMS <- names(task_names)

tk <- data.frame(task = unlist(task_names, use.names = FALSE),
                 workstream = rep(WORKSTREAMS, each = 9L), stringsAsFactors = FALSE)
n  <- nrow(tk)
d_num <- function(x) as.Date(x, origin = "1970-01-01")
wk_fwd  <- function(d) d + c(0, 0, 0, 0, 0, 2, 1)[as.integer(format(d, "%u"))]  # Sat/Sun -> Monday
wk_back <- function(d) d - c(0, 0, 0, 0, 0, 1, 2)[as.integer(format(d, "%u"))]  # Sat/Sun -> Friday
tk$owner    <- sample(rep_len(OWNERS, n))
tk$priority <- sample(PRIORITIES, n, replace = TRUE, prob = c(.16, .32, .34, .18))
tk$start    <- wk_fwd(START + sample(0:76, n, replace = TRUE))
tk$due      <- wk_back(d_num(pmin(as.numeric(tk$start) + sample(5:35, n, replace = TRUE),
                                  as.numeric(START) + 109)))
tk$est      <- sample(seq(8, 80, by = 4), n, replace = TRUE)
tk <- tk[order(tk$start, tk$due), ]; rownames(tk) <- NULL
tk$id <- sprintf("T-%02d", seq_len(n))

frac_elapsed <- pmin(1, pmax(0, as.numeric(ASOF - tk$start) / pmax(1, as.numeric(tk$due - tk$start))))
snap5 <- function(x) round(round(x / 0.05) * 0.05, 2)
tk$status <- NA_character_; tk$pct <- NA_real_
for (i in seq_len(n)) {
  u <- runif(1)
  if (tk$due[i] < ASOF - 21) {                              # long past due: finished
    tk$status[i] <- "Done"; tk$pct[i] <- 1
  } else if (tk$due[i] < ASOF) {                            # recently due: some are late
    if (u < .45)      { tk$status[i] <- "Done";        tk$pct[i] <- 1 }
    else if (u < .85) { tk$status[i] <- "In progress"; tk$pct[i] <- snap5(runif(1, .55, .95)) }
    else              { tk$status[i] <- "Blocked";     tk$pct[i] <- snap5(runif(1, .30, .70)) }
  } else if (tk$start[i] <= ASOF) {                         # running now
    if (u < .12)      { tk$status[i] <- "Blocked";     tk$pct[i] <- snap5(runif(1, .10, .60)) }
    else if (u < .20) { tk$status[i] <- "Done";        tk$pct[i] <- 1 }
    else              { tk$status[i] <- "In progress"
                        tk$pct[i] <- min(.95, max(.05, snap5(frac_elapsed[i] * runif(1, .25, 1.05)))) }
  } else if (as.numeric(tk$start[i] - ASOF) <= 7 && u < .30) {
    tk$status[i] <- "In progress"; tk$pct[i] <- snap5(runif(1, .05, .15))
  } else { tk$status[i] <- "Not started"; tk$pct[i] <- 0 }
}
# A task already in progress cannot start in the future: clamp to the as-of date, then restore start order and ids.
tk$start[tk$status == "In progress" & tk$start > ASOF] <- ASOF
tk <- tk[order(tk$start, tk$due), ]; rownames(tk) <- NULL
tk$id <- sprintf("T-%02d", seq_len(n))
stopifnot(!any(tk$status == "In progress" & tk$start > ASOF), all(tk$start <= tk$due))

# Reference implementation of the sheet formulas, used for the build-time self-check
PRIO_PTS <- setNames(PRIO_W * RISK_W[["prio"]], PRIORITIES)     # = Lists priority weight x points per weight
expected <- function(t, owner = NULL) {
  if (!is.null(owner)) t <- t[t$owner == owner, ]
  done <- t$status == "Done"; over <- !done & t$due < ASOF
  gap  <- pmax(0, pmin(1, as.numeric(ASOF - t$start) / pmax(1, as.numeric(t$due - t$start))) - t$pct)
  risk <- ifelse(done, 0, pmin(100, floor(PRIO_PTS[t$priority] + RISK_W[["gap"]] * gap +
                                          ifelse(t$due < ASOF, RISK_W[["over"]], 0) +
                                          ifelse(t$status == "Blocked", RISK_W[["blocked"]], 0) + 0.5)))
  health <- ifelse(done, "Done", ifelse(t$status == "Blocked", "Blocked",
                   ifelse(over, "Overdue", ifelse(risk >= RISK_THRESHOLD, "At risk", "On track"))))
  list(risk = unname(risk), health = health, total = nrow(t), done = sum(done), over = sum(over),
       blocked = sum(t$status == "Blocked"), hours = sum(ifelse(done, 0, t$est * (1 - t$pct))),
       ontrack = if (nrow(t)) mean(health %in% c("Done", "On track")) else NA_real_)
}
burn_expected <- function(t, owner = NULL) {                 # planned / reconstructed actual at week starts
  if (!is.null(owner)) t <- t[t$owner == owner, ]
  wk <- as.numeric(START) + 7 * (0:16); a <- as.numeric(ASOF)
  st <- as.numeric(t$start); du <- as.numeric(t$due); isdone <- t$status == "Done"
  fp <- function(d) (d >= du) + (d > st) * (d < du) * (d - st) / ((du - st) * (du > st) + (du <= st))
  planned <- vapply(wk, function(d) sum(t$est * (1 - fp(d))), numeric(1))
  actual  <- vapply(wk[wk <= a], function(d) {
    pa  <- (d >= a) + (d > st) * (d < a) * (d - st) / ((a - st) * (a > st) + (a <= st))
    eff <- isdone * ((d >= a) + (d < a) * fp(d)) + (!isdone) * t$pct * pa
    sum(t$est * (1 - eff)) }, numeric(1))
  list(planned = planned, actual = actual)
}
EXP <- expected(tk)
message(sprintf("[data] %d tasks | done %d | overdue %d | blocked %d | hours left %.0f | on-track %.0f%%",
                EXP$total, EXP$done, EXP$over, EXP$blocked, EXP$hours, 100 * EXP$ontrack))
message("[data] health: ", paste(names(table(EXP$health)), table(EXP$health), collapse = ", "))

# The Workload chart is not driven by the owner picker, so its title states what the sample shows.
open_h <- tapply(ifelse(tk$status == "Done", 0, tk$est * (1 - tk$pct)), tk$owner, sum)
TTL_WL <- sprintf("%s has the most hours left: %s of %s", names(which.max(open_h)),
                  formatC(round(max(open_h)), format = "d", big.mark = ","), formatC(round(sum(open_h)), format = "d", big.mark = ","))

# ── Layout constants (the cross-tab references derive from these; the dropdown lists on Lists start at row 12 and are written literally) ──
T_HDR <- 3L; T_ROW1 <- 4L; T_ROWN <- T_ROW1 + n - 1L; T_AGG <- 120L   # T_ROWN = last sample task; T_AGG = last prefilled row
# Every Tasks formula column, the Timeline rows, the conditional formats and the KPI/chart formulas run to row T_AGG, and each
# formula is guarded by IF($A="","",...), so a task typed into the next empty row is picked up everywhere. To go past row 120
# raise T_AGG and rerun.
# ponytail: the Tasks filter and the Owner slicer cover the sample rows only (T_ROWN): tested, a descending sort puts the empty-string
# formula rows first, so extending them to T_AGG would bury the tasks. The saved filter views do reach T_AGG: they hide rows with no ID.
# Widen the filter by hand (Data > Create a filter) after adding tasks.
TC <- list(id = 1L, task = 2L, ws = 3L, owner = 4L, prio = 5L, status = 6L, start = 7L, due = 8L,
           pct = 9L, bar = 10L, est = 11L, left = 12L, days = 13L, over = 14L, risk = 15L, health = 16L)
tr <- function(key) { cl <- col_letter(TC[[key]]); sprintf("Tasks!$%s$%d:$%s$%d", cl, T_ROW1, cl, T_AGG) }
THR_ROW <- 7L                                               # Lists row of the At-risk threshold input
ASOF_REF <- "Lists!$B$5"; START_REF <- "Lists!$B$6"; THR_REF <- sprintf("Lists!$B$%d", THR_ROW); CRIT <- "Lists!$B$8"
L_STATUS <- "Lists!$A$12:$A$15"; L_PRIO <- "Lists!$B$12:$B$15"; L_PRIOW <- "Lists!$C$12:$C$15"
L_OWNER  <- "Lists!$D$12:$D$18"; L_WS <- "Lists!$E$12:$E$16"; L_PICK <- "Lists!$F$12:$F$19"
CTRL <- c(2L, 11L)                                          # owner picker: Command Center K2
SEL <- "'Command Center'!$K$2"                              # (blank counts as "All people", see Lists!B8)
OWN_SCOPE <- sprintf('((%s=%s)+(%s="*")>0)', tr("owner"), CRIT, CRIT)     # CRIT is "*" for everyone, else the owner's name
# COUNTIFS / SUMIFS criteria for the same view. "*" matches text only, so a task with a blank owner would drop out of All people
# (OWN_SCOPE above, in array formulas, already keeps it): count by ID instead, and let everyone be "anything but (all)".
IN_VIEW <- sprintf('%s,"<>",%s,IF(%s="*","<>(all)",%s)', tr("id"), tr("owner"), CRIT, CRIT)
KV_TOTAL <- sprintf("COUNTIFS(%s)", IN_VIEW)                 # tasks in view (said in the B4 meta line, not a KPI)
LW_BAR <- 41L; LW1 <- 42L; LW_DEF <- LW1 + length(RISK_W)                  # Lists: "How risk is scored" block (heading, 4 weights, definition)
WLD_BAR <- LW_DEF + 2L; WLD1 <- WLD_BAR + 1L; WLD_LAST <- WLD1 + 1L        # Lists: "Workload limits" block (heading, overload weeks, load bar scale)
OVERLOAD_REF <- sprintf("Lists!$B$%d", WLD1); LOADBAR_REF <- sprintf("Lists!$B$%d", WLD1 + 1L)
W_REF <- sprintf("Lists!$B$%d", LW1 + 0:3)                                 # points per priority weight, gap, overdue, blocked
names(W_REF) <- names(RISK_W)
BD_HDR <- 22L; BD_ROW1 <- 23L; BD_WK_N <- 17L; BD_WK_LAST <- BD_ROW1 + BD_WK_N - 1L   # chart data on Lists
ST_HDR <- BD_ROW1 + 6L; ST_ROW <- ST_HDR + 1L                              # Lists D29:H30: all tasks by status, one row (status bar)
TL_HDR <- 4L; TL_ROW1 <- 5L; TL_ROWD <- TL_ROW1 + n - 1L; TL_ROWN <- T_AGG + 1L   # Timeline row = Tasks row + 1; TL_ROWD = last sample task
TL_W1 <- 7L; TL_WN <- TL_W1 + N_WEEKS - 1L
WL_T1_HDR <- 7L; WL_T1_ROW1 <- 8L; WL_T1_ROWN <- WL_T1_ROW1 + length(OWNERS) - 1L; WL_T1_TOT <- WL_T1_ROWN + 1L
WL_T2_HDR <- WL_T1_TOT + 3L; WL_T2_ROW1 <- WL_T2_HDR + 1L; WL_T2_ROWN <- WL_T2_ROW1 + length(OWNERS) - 1L; WL_T2_TOT <- WL_T2_ROWN + 1L
WL_NOTE <- WL_T2_TOT + 3L                                   # below the chart beside table 2
# Command Center, on the Ledger dashboard grid: A16 | B224 | C-F 112 (D 128: "Data & Reporting") | G24 | H-J 3x96 | K128 | L16
CC_WIDTHS <- c(224, 112, 128, 112, 112, 24, 96, 96, 96, 128)
CC_W <- as.integer(sum(CC_WIDTHS))                           # 1128 px: the charts fill B..K
K_ROW <- 6L; K_VAL <- K_ROW + 1L                             # KPI strip: labels 6, values 7, sub-lines 8, note 9
K_COLS <- c(2:6, 9L)                                         # on track (lead), done, overdue, blocked, at risk | hours left (I: G-H leave room for the at-risk sub-line)
kv <- function(k) sprintf("%s%d", col_letter(K_COLS[k]), K_VAL)   # a KPI value cell, e.g. kv(6) = "I7"
ST_SEC <- 11L; CH_ST <- 12L; CH_WS <- 20L                    # status section: status bar rows 12-19, workstream bars 20-32
BD_SEC <- 34L; CH_BD <- 35L; BD_NOTE <- 51L                  # burn-down: chart rows 35-50, notes 51-52
ATT_SEC <- 54L; ATT_HDR <- ATT_SEC + 1L; ATT_ROW1 <- ATT_HDR + 1L; ATT_ROWN <- ATT_ROW1 + 4L; ATT_NOTE <- ATT_ROWN + 1L
ABOUT <- ATT_NOTE + 2L
CC_LAST_ROW <- ABOUT + 7L
att <- function(col) sprintf("%s%d", col_letter(col), ATT_ROW1)   # top row of the Needs-attention table

# ── Status colours: one accent family plus one status hue (Blocked); Done is "fine", so grey ──
GREY <- hex_to_color(CHART_PALETTE[2])
ST_COL <- list("Not started" = COL_ACCENT_400, "In progress" = COL_ACCENT, "Blocked" = COL_WARNING, "Done" = GREY)
hx <- function(col) color_to_hex(col)                        # "#RRGGBB", for SPARKLINE colours
NF_DATE <- list(type = "DATE", pattern = "mmm d, yyyy"); NF_DSHORT <- list(type = "DATE", pattern = "mmm d")
NF_DEC1 <- list(type = "NUMBER", pattern = "#,##0.0"); NF_NUM0 <- list(type = "NUMBER", pattern = "0")
NF_HRS  <- list(type = "NUMBER", pattern = '#,##0" h"')
NF_VS_PLAN <- list(type = "NUMBER", pattern = '+#,##0" h vs plan";-#,##0" h vs plan";"on plan"')
NF_ZERO_BLANK <- list(type = "NUMBER", pattern = "0;-0;;@")   # chart data: a zero shows no "0" data label

# A table's column-header row with no section heading above it; `ink` adds the block's top rule.
col_header <- function(sid, r, c1, c2, num = integer(0), ink = FALSE)
  c(fmt_section(sid, r, c1, c2, numeric_cols = num, heading = FALSE),
    if (ink) list(fmt_borders(sid, r, r, c1, c2, top = BORDER_INK)))
# Title rows for the tabs whose column A holds data (fmt_tab_base() puts its title block in column B).
title_a <- function(sid, note_col = 1L)
  list(apply_style(sid, 1, 1, 1, 1, STYLE_TITLE), fmt_row_height(sid, 1, 1, 36L),
       apply_style(sid, 2, 2, note_col, note_col, STYLE_NOTE), fmt_row_height(sid, 2, 2, 22L))

# ── Connect and create/open the sheet ────────────────────────────────────────
gs_connect(USER_EMAIL)
# gs_open_or_create() stops before changing anything if SHEET_ID is neither a file titled SHEET_TITLE nor one with all TABS,
# or if that file's locale is not en_US (number/date parsing and TEXT() formats assume it).
# A new file gets en_US and Etc/GMT, a neutral zone, so copies of the file do not carry the author's region. A reused file keeps its
# own zone: all dates here are date-only and nothing uses TODAY() or NOW(), so no value depends on it.
ss <- gs_open_or_create(SHEET_TITLE, TABS, time_zone = "Etc/GMT", locale = "en_US")
ss_id <- as.character(ss)
cat("SHEET_ID=", ss_id, "\n", sep = "")
gs_reset_tabs(ss, TABS)                               # rebuilding in place must not stack charts, rules, protections or filter views; only our tabs
sid_cc <- get_sheet_id(ss, TAB_CC); sid_t <- get_sheet_id(ss, TAB_TASKS); sid_tl <- get_sheet_id(ss, TAB_TL)
sid_wl <- get_sheet_id(ss, TAB_WL); sid_l <- get_sheet_id(ss, TAB_LISTS)
# Theme first: the font and the chart colours follow it.
batch_format(ss, list(do.call(fmt_theme_colors, THEME_DEFAULT)), strict = TRUE)

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: buffer every cell write (values and formulas), then flush once
# ══════════════════════════════════════════════════════════════════════════════

# ---- Lists -------------------------------------------------------------------
write_cell(ss, TAB_LISTS, 1, 1, "Lists and settings")
write_cell(ss, TAB_LISTS, 2, 1, paste0("Sample data. Blue cells are inputs: dates, threshold, risk weights, priority weights, workload limits. Grey lists feed the dropdowns; ",
  "their names are matched exactly by the formulas and by the Tasks rows, so rename one only together with the Tasks column."))
write_cell(ss, TAB_LISTS, 4, 1, "Settings")
write_cell(ss, TAB_LISTS, 5, 1, "As-of date");                  write_cell(ss, TAB_LISTS, 5, 2, format(ASOF))
write_cell(ss, TAB_LISTS, 5, 3, "Fixed so this sample never changes. To make the sheet live, replace this cell with =TODAY().")
write_cell(ss, TAB_LISTS, 6, 1, "Timeline start (a Monday)");   write_cell(ss, TAB_LISTS, 6, 2, format(START))
write_cell(ss, TAB_LISTS, 6, 3, "First week on the Timeline and the burn-down chart.")
write_cell(ss, TAB_LISTS, THR_ROW, 1, "At-risk threshold");     write_cell(ss, TAB_LISTS, THR_ROW, 2, RISK_THRESHOLD)
write_cell(ss, TAB_LISTS, THR_ROW, 3, sprintf("An open task with a risk score at or above this is flagged At risk. The score is defined under How risk is scored, row %d.", LW_BAR))
write_cell(ss, TAB_LISTS, 8, 1, "Owner criterion (formula)")
write_cell(ss, TAB_LISTS, 8, 2, sprintf('=IF(OR(%s="",%s="%s"),"*",%s)', SEL, SEL, ALL_LABEL, SEL))
write_cell(ss, TAB_LISTS, 8, 3, "Driven by the Owner picker on the Command Center. A blank picker counts as All people.")
write_cell(ss, TAB_LISTS, 10, 1, "Dropdown sources")
write_block(ss, TAB_LISTS, 11, 1, rbind(c("Status", "Priority", "Priority weight", "Owner", "Workstream", "Owner view options")))
write_block(ss, TAB_LISTS, 12, 1, matrix(STATUSES, ncol = 1))
write_block(ss, TAB_LISTS, 12, 2, data.frame(PRIORITIES, PRIO_W))        # data.frame keeps the weights numeric
write_block(ss, TAB_LISTS, 12, 4, matrix(OWNERS, ncol = 1))
write_block(ss, TAB_LISTS, 12, 5, matrix(WORKSTREAMS, ncol = 1))
write_cell(ss, TAB_LISTS, 12, 6, ALL_LABEL)
write_block(ss, TAB_LISTS, 13, 6, matrix(sprintf("=D%d", 12:18), ncol = 1))
write_cell(ss, TAB_LISTS, 20, 1, sprintf("The lists hold %d owners and %d workstreams, set in the build script (OWNERS, WORKSTREAMS): adding one means editing the script and rerunning it.",
                                         length(OWNERS), length(WORKSTREAMS)))
write_cell(ss, TAB_LISTS, 21, 1, "Chart data (formulas, do not edit)")
write_block(ss, TAB_LISTS, BD_HDR, 1, rbind(c("Status (count)", "Tasks")))
# The status bar's legend label carries the live count: "Done  (14)"
write_block(ss, TAB_LISTS, BD_ROW1, 1, cbind(sprintf('=A%d&"  ("&B%d&")"', 12:15, BD_ROW1:(BD_ROW1 + 3L)),
  sprintf('=COUNTIFS(%s,A%d,%s)', tr("status"), 12:15, IN_VIEW)))
write_block(ss, TAB_LISTS, BD_HDR, 4, rbind(c("Workstream", sprintf("=A%d", 12:15))))
ws_rows <- BD_ROW1:(BD_ROW1 + length(WORKSTREAMS) - 1L)
write_block(ss, TAB_LISTS, BD_ROW1, 4, cbind(sprintf("=E%d", 12:16), sapply(5:8, function(cc)
  sprintf('=COUNTIFS(%s,$D%d,%s,%s$%d,%s)', tr("ws"), ws_rows, tr("status"), col_letter(cc), BD_HDR, IN_VIEW))))
# The same counts as one row (series = statuses) for the 100% status bar on the Command Center
write_block(ss, TAB_LISTS, ST_HDR, 4, rbind(c("Status", sprintf("=A%d", BD_ROW1:(BD_ROW1 + 3L))),
                                            c("All tasks", sprintf("=B%d", BD_ROW1:(BD_ROW1 + 3L)))))
write_block(ss, TAB_LISTS, BD_HDR, 10, rbind(c("Week start", "Week", "Planned", "Actual (reconstructed)")))
wk_rows <- BD_ROW1:BD_WK_LAST
fp_expr <- "(d>=du)+(d>st)*(d<du)*(d-st)/((du-st)*(du>st)+(du<=st))"           # share of a task planned complete at date d
# NB: LET bindings are scalar context, so every computed array is wrapped in ARRAYFORMULA() (plain ranges are fine)
let_base <- sprintf("st,%s,du,%s,hrs,%s,own,ARRAYFORMULA(%s)", tr("start"), tr("due"), tr("est"), OWN_SCOPE)
write_block(ss, TAB_LISTS, BD_ROW1, 10, cbind(
  c("=$B$6", sprintf("=J%d+7", wk_rows[-length(wk_rows)])),
  sprintf('=TEXT(J%d,"mmm d")', wk_rows),
  sprintf('=LET(d,$J%d,%s,fp,ARRAYFORMULA(%s),SUMPRODUCT(own*hrs*(1-fp)))', wk_rows, let_base, fp_expr)))
# ponytail: "actual" is a reconstruction (no per-week history exists); log real weekly snapshots if exact history matters.
# Actual: one spilled formula; cells after the as-of week stay truly empty so the chart line simply stops.
# Reconstruction: a not-done task is assumed to have progressed steadily from its start to its current % complete;
# a done task follows its plan and is complete at the as-of date.
write_cell(ss, TAB_LISTS, BD_ROW1, 13, sprintf(paste0(
  '=IFERROR(MAP(FILTER($J$%d:$J$%d,$J$%d:$J$%d<=%s),LAMBDA(d,LET(%s,pc,%s,sx,%s,asof,%s,fp,ARRAYFORMULA(%s),',
  'pa,ARRAYFORMULA((d>=asof)+(d>st)*(d<asof)*(d-st)/((asof-st)*(asof>st)+(asof<=st))),',
  'eff,ARRAYFORMULA((sx="Done")*((d>=asof)+(d<asof)*fp)+(sx<>"Done")*pc*pa),SUMPRODUCT(own*hrs*(1-eff))))),"")'),
  BD_ROW1, BD_WK_LAST, BD_ROW1, BD_WK_LAST, ASOF_REF, let_base, tr("pct"), tr("status"), ASOF_REF, fp_expr))

# How risk is scored: the weights the Tasks!O formula reads (inputs), below the chart data
write_cell(ss, TAB_LISTS, LW_BAR, 1, "How risk is scored (0 to 100)")
write_block(ss, TAB_LISTS, LW1, 1, data.frame(
  c("Points per priority weight", "Schedule-gap weight", "Overdue bonus", "Blocked bonus"), unname(RISK_W),
  c("Priority points = this x the Priority weight in the table above.",
    "Points when progress trails the elapsed share of the schedule by 100% (scaled down proportionally).",
    "Added to an open task that is past its due date.",
    "Added to a task whose status is Blocked.")))
write_cell(ss, TAB_LISTS, LW_DEF, 1, paste0("Risk score = priority points + schedule-gap points + overdue bonus + blocked bonus, capped at 100. ",
  sprintf("Done tasks score 0. At or above the At-risk threshold (row %d) a task is flagged At risk.", THR_ROW)))

# Workload limits: the two numbers the Workload tab reads (inputs)
write_cell(ss, TAB_LISTS, WLD_BAR, 1, "Workload limits")
write_block(ss, TAB_LISTS, WLD1, 1, data.frame(
  c("Overload above (weeks)", "Load bar full at (weeks)"), c(OVERLOAD_WEEKS, LOAD_BAR_WEEKS),
  c("A person whose hours left need more weeks than this turns red on the Workload tab (number and bar).",
    "The Workload load bar is full at this many weeks of work. Keep it above the overload limit.")))

# ---- Tasks -------------------------------------------------------------------
write_cell(ss, TAB_TASKS, 1, 1, "Tasks (sample data)")
write_cell(ss, TAB_TASKS, 2, 1, "Input")
write_cell(ss, TAB_TASKS, 2, 2, paste0("Blue cells are inputs you can edit. Black text is a formula (editing it shows a warning). ",
  "Done rows turn grey. To add a task, type an ID and its inputs in the next empty row: the formulas are ready down to row ", T_AGG, "."))
hdr_tasks <- c("ID", "Task", "Workstream", "Owner", "Priority", "Status", "Start", "Due", "% done", "Progress",
               "Est. hours", "Hours left", "Days left", "Overdue", "Risk score", "Health")
write_block(ss, TAB_TASKS, T_HDR, 1, rbind(hdr_tasks))
write_block(ss, TAB_TASKS, T_ROW1, 1, data.frame(tk$id, tk$task, tk$workstream, tk$owner, tk$priority, tk$status,
                                              format(tk$start), format(tk$due), tk$pct))
write_block(ss, TAB_TASKS, T_ROW1, 11, matrix(tk$est, ncol = 1))
rf <- T_ROW1:T_AGG                                      # formula rows: the sample tasks plus the empty rows ready for new ones
guard <- function(f) paste0('=IF($A', rf, '="","",', f, ')')   # empty ID -> empty row (no false "Overdue", no negative days)
# progress on a grey track: accent while open, the warning mark when blocked, grey once done
bar_f <- vapply(rf, function(r) fraw(f_sparkline(sprintf("{I%d,1-I%d}", r, r), list(charttype = "bar",
  color1 = I(sprintf('IF(F%d="Done","%s",IF(F%d="Blocked","%s","%s"))', r, hx(ST_COL$Done), r, hx(COL_WARNING), hx(COL_ACCENT))),
  color2 = hx(COL_SEP_SUBTLE)))), "")
write_block(ss, TAB_TASKS, T_ROW1, 10, matrix(guard(bar_f), ncol = 1))
write_block(ss, TAB_TASKS, T_ROW1, 12, cbind(
  guard(sprintf('IF(F%d="Done",0,K%d*(1-I%d))', rf, rf, rf)),
  guard(sprintf('IF(F%d="Done","",H%d-%s)', rf, rf, ASOF_REF)),
  guard(sprintf('IF(AND(F%d<>"Done",H%d<%s),"Overdue","")', rf, rf, ASOF_REF)),
  # risk = priority weight x W_prio + W_gap x schedule gap + W_over if overdue + W_blocked if blocked, capped at 100 (weights: Lists)
  guard(sprintf(paste0('IFERROR(IF(F%d="Done",0,MIN(100,ROUND(INDEX(%s,MATCH(E%d,%s,0))*%s',
                   '+%s*MAX(0,MIN(1,(%s-G%d)/MAX(1,H%d-G%d))-I%d)+IF(H%d<%s,%s,0)+IF(F%d="Blocked",%s,0),0))),0)'),
            rf, L_PRIOW, rf, L_PRIO, W_REF[["prio"]], W_REF[["gap"]], ASOF_REF, rf, rf, rf, rf, rf, ASOF_REF, W_REF[["over"]],
            rf, W_REF[["blocked"]])),
  guard(sprintf('IF(F%d="Done","Done",IF(F%d="Blocked","Blocked",IF(N%d="Overdue","Overdue",IF(O%d>=%s,"At risk","On track"))))',
            rf, rf, rf, rf, THR_REF))))

# ---- Timeline ----------------------------------------------------------------
write_cell(ss, TAB_TL, 1, 1, "Timeline (sample data)")
write_cell(ss, TAB_TL, 2, 1, "Weekly Gantt view, drawn by conditional formatting from each task's start and due dates. The grey column is the as-of week.")
write_cell(ss, TAB_TL, 3, 2, "As-of date (from Lists)")
write_cell(ss, TAB_TL, 3, 3, sprintf("=%s", ASOF_REF))
TL_KEY <- TL_WN - 11L                                   # colour key on row 2: a swatch cell (the bar fill) and its label, x4
for (i in seq_along(STATUSES)) write_cell(ss, TAB_TL, 2, TL_KEY + 3L * (i - 1L) + 1L, STATUSES[i])
write_block(ss, TAB_TL, TL_HDR, 1, rbind(c("ID", "Task", "Owner", "Status", "Start", "Due")))
write_cell(ss, TAB_TL, TL_HDR, TL_W1, sprintf("=%s", START_REF))
write_block(ss, TAB_TL, TL_HDR, TL_W1 + 1L, rbind(sprintf("=%s4+7", sapply(TL_W1:(TL_WN - 1L), col_letter))))
write_block(ss, TAB_TL, 3, TL_W1, rbind(sprintf('=IF(AND($C$3>=%s$4,$C$3<=%s$4+6),"▼","")',
                                            sapply(TL_W1:TL_WN, col_letter), sapply(TL_W1:TL_WN, col_letter))))
tcols <- c("A", "B", "D", "F", "G", "H")
write_block(ss, TAB_TL, TL_ROW1, 1, sapply(tcols, function(cl) sprintf('=IF(Tasks!$A%d="","",Tasks!%s%d)', rf, cl, rf)))

# ---- Workload ----------------------------------------------------------------
w_rng <- function(cl) sprintf("$%s$%d:$%s$%d", cl, WL_T1_ROW1, cl, WL_T1_ROWN)
write_cell(ss, TAB_WL, 2, 2, "Workload")
write_cell(ss, TAB_WL, 3, 2, sprintf(paste0('=LET(w,%s,lim,%s,n,COUNTIF(w,">"&lim),IF(COUNT(w)=0,"No capacity is set.",',
  'INDEX(%s,MATCH(MAX(w),w,0))&" has the longest queue: "&TEXT(MAX(w),"0.0")&" weeks of work at current capacity; "&',
  'IF(n=0,"nobody is",n&" of "&ROWS(w)&IF(n=1," person is"," people are"))&" over the "&lim&"-week limit."))'),
  w_rng("K"), OVERLOAD_REF, w_rng("B")))
write_cell(ss, TAB_WL, 4, 2, "Sample data · every figure is a formula on the Tasks tab except the blue capacity inputs · Done tasks carry no hours")
write_cell(ss, TAB_WL, WL_T1_HDR - 1L, 2, "Tasks by owner and status")
write_block(ss, TAB_WL, WL_T1_HDR, 2, rbind(c("Owner", sprintf("=Lists!$A$%d", 12:15), "Total", "Overdue", "Hours left",
                                         "Capacity (h/wk)", "Weeks of work", sprintf('="Load bar ("&%s&" weeks = full)"', LOADBAR_REF))))
ow_r <- WL_T1_ROW1:WL_T1_ROWN
write_block(ss, TAB_WL, WL_T1_ROW1, 2, data.frame(                                # data.frame keeps CAPACITY numeric
  sprintf("=Lists!$D$%d", 12:18),
  sapply(3:6, function(cc) sprintf('=COUNTIFS(%s,$B%d,%s,%s$%d)', tr("owner"), ow_r, tr("status"), col_letter(cc), WL_T1_HDR)),
  sprintf("=SUM(C%d:F%d)", ow_r, ow_r),
  sprintf('=COUNTIFS(%s,$B%d,%s,"Overdue")', tr("owner"), ow_r, tr("over")),
  sprintf('=SUMIFS(%s,%s,$B%d)', tr("left"), tr("owner"), ow_r),
  CAPACITY,
  sapply(ow_r, function(rr) f_safe_div(sprintf("I%d", rr), sprintf("J%d", rr))),
  # bar = weeks of work on a fixed scale (the Lists load-bar input); red above the Lists overload limit, like the number beside it
  vapply(ow_r, function(rr) f_sparkline(sprintf("K%d", rr), list(charttype = "bar", max = I(LOADBAR_REF),
    color1 = I(sprintf('IF(K%d>%s,"%s","%s")', rr, OVERLOAD_REF, hx(COL_NEGATIVE), hx(COL_ACCENT))), color2 = hx(COL_SEP_SUBTLE)), iferror = TRUE), "")))
write_block(ss, TAB_WL, WL_T1_TOT, 2, rbind(c("Total",
  sapply(3:10, function(cc) sprintf("=SUM(%s%d:%s%d)", col_letter(cc), WL_T1_ROW1, col_letter(cc), WL_T1_ROWN)),
  f_safe_div(sprintf("I%d", WL_T1_TOT), sprintf("J%d", WL_T1_TOT)), NA)))
write_cell(ss, TAB_WL, WL_T2_HDR - 1L, 2, "Hours remaining by owner and status")
write_block(ss, TAB_WL, WL_T2_HDR, 2, rbind(c("Owner", sprintf("=Lists!$A$%d", 12:14), "Total")))
ow2 <- WL_T2_ROW1:WL_T2_ROWN
write_block(ss, TAB_WL, WL_T2_ROW1, 2, cbind(
  sprintf("=$B%d", ow_r),
  sapply(3:5, function(cc) sprintf('=SUMIFS(%s,%s,$B%d,%s,%s$%d)', tr("left"), tr("owner"), ow2, tr("status"), col_letter(cc), WL_T2_HDR)),
  sprintf("=SUM(C%d:E%d)", ow2, ow2)))
write_block(ss, TAB_WL, WL_T2_TOT, 2, rbind(c("Total", sapply(3:6, function(cc)
  sprintf("=SUM(%s%d:%s%d)", col_letter(cc), WL_T2_ROW1, col_letter(cc), WL_T2_ROWN)))))
write_cell(ss, TAB_WL, WL_NOTE, 2, sprintf('="Note: capacity is an input. Weeks of work = hours left / capacity; more than "&%s&" weeks turns red (number and bar, total row included)."', OVERLOAD_REF))
write_cell(ss, TAB_WL, WL_NOTE + 1L, 2, "The limit and the load-bar scale are inputs on Lists. Tasks with no owner count on the Command Center only.")

# ---- Command Center ----------------------------------------------------------
cnt_status <- function(s) sprintf('COUNTIFS(%s,%s,"%s")', IN_VIEW, tr("status"), s)
# Blocked wins over Overdue in the Health column, so a task that is both is counted in both: the finding and the sub-line say so
OVER_BLOCKED <- sprintf('COUNTIFS(%s,%s,"Overdue",%s,"Blocked")', IN_VIEW, tr("over"), tr("status"))
bd_col <- function(cl) sprintf("Lists!$%s$%d:$%s$%d", cl, BD_ROW1, cl, BD_WK_LAST)
# hours left minus the plan, at the last actual point (the week start on or before the as-of date)
vs_plan <- sprintf('LET(k,COUNT(%s),IF(k=0,"",INDEX(%s,k)-INDEX(%s,k)))', bd_col("M"), bd_col("M"), bd_col("L"))
write_cell(ss, TAB_CC, 2, 2, sprintf('="Ops command center, "&IF(%s="*","all people",%s)', CRIT, CRIT))
write_cell(ss, TAB_CC, CTRL[1], CTRL[2] - 1L, "Owner")
write_cell(ss, TAB_CC, CTRL[1], CTRL[2], ALL_LABEL)
# The finding: one live sentence built from the KPIs and the top row of the Needs-attention table
write_cell(ss, TAB_CC, 3, 2, sprintf(paste0('=IF(%1$s=0,"No tasks in this view.",TEXT(%2$s,"0%%")&" of tasks are done or on schedule; "&',
  '%3$s&" overdue"&IF(%11$s>0," ("&%11$s&" also blocked)","")&", "&%4$s&" blocked and "&%10$s&" at risk. "&IF(%5$s="","No open tasks remain.",IF(AND(%8$s<%9$s,%3$s+%4$s=0),',
  '"Nothing at risk: the highest risk score is "&%8$s&" of 100 (flagged from "&%9$s&").",',
  '"Top risk: "&%5$s&" ("&%6$s&", "&IF(%7$s="","no owner",%7$s)&"), risk score "&%8$s&" of 100.")))'),
  KV_TOTAL, kv(1), kv(3), kv(4), att(2), att(3), att(5), att(10), THR_REF, kv(5), OVER_BLOCKED))
write_cell(ss, TAB_CC, 4, 2, sprintf(paste0('="Sample data · as of "&TEXT(%1$s,"mmm d, yyyy")&" · "&%2$s&IF(%2$s=1," task "," tasks ")&',
  'IF(%3$s="*","across "&COUNTA(%4$s)&" people","assigned to "&%3$s)&" · every number is a live formula · built %5$s · View only? File > Make a copy to use the owner picker"'),
  ASOF_REF, KV_TOTAL, CRIT, L_OWNER, Sys.Date()))
k_lab <- c("On track", "Done", "Overdue", "Blocked", "At risk", "Hours left")
k_val <- c(
  f_safe_div(sprintf('(COUNTIFS(%s,%s,"On track")+%s)', IN_VIEW, tr("health"), cnt_status("Done")), KV_TOTAL),
  f_safe_div(cnt_status("Done"), KV_TOTAL),
  sprintf('=COUNTIFS(%s,%s,"Overdue")', IN_VIEW, tr("over")),
  sprintf("=%s", cnt_status("Blocked")),
  sprintf('=COUNTIFS(%s,%s,"At risk")', IN_VIEW, tr("health")),
  sprintf("=SUMIFS(%s,%s)", tr("left"), IN_VIEW))
k_sub <- c(
  "done or on schedule",
  sprintf('=%s&" of "&%s&" tasks"', cnt_status("Done"), KV_TOTAL),
  sprintf('=IF(%1$s>0,%1$s&" also blocked","past due, not done")', OVER_BLOCKED),
  "waiting on others",
  sprintf('="score "&%s&"+, not late or blocked"', THR_REF),   # Overdue and Blocked take precedence in Health
  paste0("=", vs_plan))
for (k in seq_along(K_COLS)) {
  write_cell(ss, TAB_CC, K_ROW, K_COLS[k], k_lab[k]); write_cell(ss, TAB_CC, K_VAL, K_COLS[k], k_val[k])
  write_cell(ss, TAB_CC, K_VAL + 1L, K_COLS[k], k_sub[k])
}
write_cell(ss, TAB_CC, K_VAL + 2L, 2, sprintf('="Hours left are of "&TEXT(SUMIFS(%s,%s),"#,##0")&" h estimated, compared with the planned burn-down for "&TEXT(%s,"mmm d")&": red is behind plan, green is ahead."',
                                              tr("est"), IN_VIEW, ASOF_REF))
write_cell(ss, TAB_CC, ST_SEC, 2, "Status by workstream")
write_cell(ss, TAB_CC, ST_SEC, 11, sprintf('=%1$s&IF(%1$s=1," task"," tasks")&" in view"', KV_TOTAL))
write_cell(ss, TAB_CC, BD_SEC, 2, "Burn-down: hours remaining")
write_cell(ss, TAB_CC, BD_SEC, 11, sprintf(paste0('=LET(k,COUNT(%s),IF(k=0,"",LET(x,INDEX(%s,k)-INDEX(%s,k),',
  'IF(ROUND(x,0)>0,"Behind plan by "&TEXT(x,"#,##0")&" h",IF(ROUND(x,0)<0,"Ahead of plan by "&TEXT(-x,"#,##0")&" h","On plan"))&" at "&TEXT(INDEX(%s,k),"mmm d"))))'),
  bd_col("M"), bd_col("M"), bd_col("L"), bd_col("J")))
write_cell(ss, TAB_CC, BD_NOTE, 2, "Planned: a straight-line plan between each task's start and due date. The actual line stops at the as-of week.")
write_cell(ss, TAB_CC, BD_NOTE + 1L, 2, "Actual: hours left, reconstructed by assuming steady progress from each task's start to its current % complete.")
write_cell(ss, TAB_CC, ATT_SEC, 2, "Needs attention: top 5 open tasks by risk score")
ATT_COLS <- list(c(2, 2), c(3, 1), c(4, 3), c(5, 4), c(6, 8), c(8, 9), c(9, 13), c(10, 15), c(11, 16))   # dashboard col, Tasks col
write_block(ss, TAB_CC, ATT_HDR, 2, rbind(c("Task", "ID", "Workstream", "Owner", "Due", NA, "% done", "Days left", "Risk", "Health")))
att_formula <- function(i, col) sprintf(paste0('=IFERROR(INDEX(SORT(FILTER(Tasks!$A$%d:$P$%d,%s<>"",%s<>"Done",%s),15,FALSE,8,TRUE),%d,%d),"")'),
                                        T_ROW1, T_AGG, tr("id"), tr("status"), OWN_SCOPE, i, col)
for (i in 1:5) for (cc in ATT_COLS) write_cell(ss, TAB_CC, ATT_ROW1 + i - 1L, cc[1], att_formula(i, cc[2]))
write_cell(ss, TAB_CC, ATT_NOTE, 2, sprintf("Risk score 0-100 = priority + schedule gap + overdue and blocked bonuses (weights on Lists, row %d). Days left below 0 are days late.", LW_BAR))
write_cell(ss, TAB_CC, ABOUT, 2, "About this sample")
about <- c("Sample data: every name, task, date and hour here is synthetic, generated in R with a fixed random seed.",
           "Pick a person in Owner (top right) to filter this page, or edit the blue cells on the Tasks tab, and everything recalculates.",
           "The Tasks tab also has an Owner slicer and saved views under Data > Filter views. To add a task, fill the next empty row on Tasks: its formulas are ready.",
           sprintf("The Tasks filter and Owner slicer stop at row %d, so widen them (Data > Create a filter) after adding rows; the saved views already cover them.", T_ROWN))
for (k in seq_along(about)) write_cell(ss, TAB_CC, ABOUT + k, 2, about[k])   # the two credit lines follow, written as links

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: flush, then one formatting batch per tab
# ══════════════════════════════════════════════════════════════════════════════
flush_writes(ss, strict = TRUE)
Sys.sleep(4)

# ---- Lists -------------------------------------------------------------------
fmt_lists <- function(sid) {
  b <- new_batch()
  b$push(fmt_tab_base(sid, 60L, 13L, "data", title_row = NULL, inputs = TRUE, freeze_rows = 2L))
  b$push(fmt_col_widths(sid, c(215, 130, 130, 150, 130, 150, 100, 100, 30, 100, 80, 90, 120)))
  b$push(title_a(sid))
  for (r in c(4L, 10L, LW_BAR, WLD_BAR)) b$push(fmt_section(sid, r, 1, 6, header = FALSE))
  b$push(fmt_section(sid, 21, 1, 13, header = FALSE))
  # settings: label, value, note
  b$push(fmt_table_body(sid, 5, 8, 1, 3))
  b$push(apply_style(sid, 5, 7, 2, 2, STYLE_INPUT, halign = "RIGHT"))
  b$push(fmt_cells(sid, 5, 6, 2, 2, numfmt = NF_DATE)); b$push(fmt_cells(sid, 7, 7, 2, 2, numfmt = NF_NUM0))
  b$push(fmt_cells(sid, 8, 8, 2, 2, halign = "RIGHT", font_color = COL_TEXT_3))
  b$push(apply_style(sid, 5, 8, 3, 3, STYLE_NOTE))
  # dropdown sources: only the priority weights are inputs; every name is matched literally by formulas and Tasks rows (grey = fixed)
  b$push(col_header(sid, 11, 1, 6, num = 3))
  b$push(fmt_table_body(sid, 12, 19, 1, 6))
  for (g in list(c(15, 1, 2), c(18, 4, 4), c(16, 5, 5), c(19, 6, 6))) b$push(apply_style(sid, 12, g[1], g[2], g[3], STYLE_GRAYED_OUT))
  b$push(apply_style(sid, 12, 15, 3, 3, STYLE_INPUT, halign = "RIGHT"))
  b$push(apply_style(sid, 20, 20, 1, 1, STYLE_NOTE))
  # chart data
  for (g in list(c(1, 2, BD_ROW1 + 3L), c(4, 8, BD_ROW1 + 4L), c(10, 13, BD_WK_LAST))) {
    b$push(col_header(sid, BD_HDR, g[1], g[2], num = if (g[1] == 10) 12:13 else (g[1] + 1L):g[2]))
    b$push(fmt_table_body(sid, BD_ROW1, g[3], g[1], g[2], numeric_cols = if (g[1] == 10) 12:13 else (g[1] + 1L):g[2],
                          numfmt = if (g[1] == 10) NUMFMT_INT else NF_ZERO_BLANK))   # zeros blank: no "0" data labels
  }
  b$push(fmt_row_height(sid, BD_HDR, BD_HDR, 36L))
  b$push(col_header(sid, ST_HDR, 4, 8, num = 5:8))
  b$push(fmt_table_body(sid, ST_ROW, ST_ROW, 4, 8, numeric_cols = 5:8, numfmt = NF_ZERO_BLANK))
  b$push(fmt_cells(sid, BD_ROW1, BD_WK_LAST, 10, 10, numfmt = NF_DSHORT, halign = "LEFT"))
  # how risk is scored, workload limits: label, input, note
  for (g in list(c(LW1, LW1 + 3L), c(WLD1, WLD_LAST))) {
    b$push(fmt_table_body(sid, g[1], g[2], 1, 3))
    b$push(apply_style(sid, g[1], g[2], 2, 2, STYLE_INPUT, halign = "RIGHT", numfmt = NF_NUM0))
    b$push(apply_style(sid, g[1], g[2], 3, 3, STYLE_NOTE))
  }
  b$push(apply_style(sid, LW_DEF, LW_DEF, 1, 1, STYLE_NOTE))
  b$get()
}

# ---- Tasks -------------------------------------------------------------------
fmt_tasks <- function(sid) {
  IN_LAST <- T_ROWN + 10L        # the input fill covers the sample rows plus a margin; blue text runs to T_AGG
  b <- new_batch()
  b$push(fmt_tab_base(sid, T_AGG, 16L, "data", title_row = NULL, inputs = TRUE, freeze_rows = T_HDR, freeze_cols = 2L))
  b$push(fmt_col_widths(sid, c(60, 270, 140, 80, 72, 100, 100, 100, 70, 110, 76, 84, 76, 80, 76, 96)))
  b$push(title_a(sid, 2L))
  b$push(apply_style(sid, 2, 2, 1, 1, STYLE_INPUT, halign = "CENTER", bold = TRUE))   # the key: this look = an input
  b$push(col_header(sid, T_HDR, 1, 16, num = c(9, 11:13, 15), ink = TRUE)); b$push(fmt_row_height(sid, T_HDR, T_HDR, 30L))
  b$push(fmt_row_height(sid, T_ROW1, T_AGG, 24L))
  b$push(fmt_cells(sid, T_ROW1, T_AGG, 1, 9, font_color = COL_INPUT_FG)); b$push(fmt_cells(sid, T_ROW1, T_AGG, 11, 11, font_color = COL_INPUT_FG))
  for (g in list(c(1, 9), c(11, 11))) b$push(apply_style(sid, T_ROW1, IN_LAST, g[1], g[2], STYLE_INPUT))
  b$push(fmt_borders(sid, T_ROW1, IN_LAST, 1, 11, inner_h = list(style = "SOLID", color = COL_WHITE)))   # rows stay readable on the fill
  b$push(fmt_cells(sid, T_ROW1, T_AGG, 7, 8, numfmt = NF_DATE, halign = "LEFT"))
  b$push(fmt_cells(sid, T_ROW1, T_AGG, 9, 9, numfmt = NUMFMT_PCT_WHOLE, halign = "RIGHT"))
  b$push(fmt_cells(sid, T_ROW1, T_AGG, 11, 11, numfmt = NUMFMT_INT, halign = "RIGHT"))
  b$push(fmt_cells(sid, T_ROW1, T_AGG, 12, 12, numfmt = NF_DEC1, halign = "RIGHT"))
  b$push(fmt_cells(sid, T_ROW1, T_AGG, 13, 13, numfmt = NF_NUM0, halign = "RIGHT"))
  b$push(fmt_cells(sid, T_ROW1, T_AGG, 15, 15, numfmt = NF_NUM0, halign = "RIGHT"))
  b$push(fmt_cells(sid, T_HDR, T_AGG, 14, 14, halign = "CENTER"))   # Overdue: clear of the right-aligned Days left
  b$push(list(
    fmt_dropdown_range(sid, T_ROW1, T_AGG, 3, 3, paste0("=", L_WS)),
    fmt_dropdown_range(sid, T_ROW1, T_AGG, 4, 4, paste0("=", L_OWNER)),
    fmt_dropdown_range(sid, T_ROW1, T_AGG, 5, 5, paste0("=", L_PRIO)),
    fmt_dropdown_range(sid, T_ROW1, T_AGG, 6, 6, paste0("=", L_STATUS)),
    fmt_validation(sid, T_ROW1, T_AGG, 9, 9, "NUMBER_BETWEEN", c(0, 1), input_message = "Enter 0% to 100%"),
    fmt_validation(sid, T_ROW1, T_AGG, 7, 8, "DATE_IS_VALID", input_message = "Enter a date"),
    fmt_basic_filter(sid, T_HDR, T_ROWN, 1, 16)))
  # Rules: the first one listed wins per cell (b$cf numbers them 0, 1, 2... for this tab).
  # A task with an ID but no owner shows under All people only: flag the empty Owner cell.
  b$cf(fmt_cond_formula, sid, T_ROW1, T_AGG, 4, 4, '=AND($A4<>"",$D4="")', bg_color = STATUS$negative$fill)
  for (cc in list(c(1L, 9L), c(11L, 14L)))              # skip column J: the progress-bar sparkline keeps its own colours
    b$cf(fmt_cond_formula, sid, T_ROW1, T_AGG, cc[1L], cc[2L], '=$F4="Done"', font_color = COL_TEXT_3)
  b$cf(fmt_cond_formula, sid, T_ROW1, T_AGG, 8, 8, '=$N4="Overdue"', font_color = COL_NEGATIVE, bold = TRUE)
  b$cf(fmt_cond_color_scale, sid, T_ROW1, T_AGG, 15, 15, SCALE_HEAT$min_color, SCALE_HEAT$mid_color, SCALE_HEAT$max_color)
  # Health chips last: colour only where there is risk (On track and Done stay grey text)
  b$push(fmt_status(sid, T_ROW1, T_AGG, 16, 16, c(Overdue = "negative", Blocked = "warning", "At risk" = "warning"), index = 5L))
  b$get()
}

# ---- Timeline ----------------------------------------------------------------
fmt_timeline <- function(sid) {
  b <- new_batch()
  b$push(fmt_tab_base(sid, TL_ROWN + 5L, TL_WN, "model", title_row = NULL, freeze_rows = TL_HDR, freeze_cols = 2L))
  b$push(c(fmt_col_widths(sid, c(52, 220, 72, 84, 70, 70)), fmt_col_widths(sid, rep(50, N_WEEKS), start_col = TL_W1)))
  b$push(title_a(sid))
  for (i in seq_along(STATUSES)) {                      # colour key: swatch = the bar fill, then the status name
    c1 <- TL_KEY + 3L * (i - 1L)
    b$push(fmt_cells(sid, 2, 2, c1, c1, bg_color = ST_COL[[STATUSES[i]]]))
    b$push(apply_style(sid, 2, 2, c1 + 1L, c1 + 1L, STYLE_NOTE))
  }
  b$push(fmt_row_height(sid, 3, 3, 22L))
  b$push(apply_style(sid, 3, 3, 2, 2, STYLE_NOTE, halign = "RIGHT"))
  b$push(fmt_cells(sid, 3, 3, 3, 3, numfmt = NF_DSHORT, halign = "LEFT", bold = TRUE))
  b$push(fmt_cells(sid, 3, 3, TL_W1, TL_WN, halign = "CENTER", font_color = COL_INK))
  b$push(col_header(sid, TL_HDR, 1, TL_WN, ink = TRUE))
  b$push(fmt_cells(sid, TL_HDR, TL_HDR, TL_W1, TL_WN, numfmt = NF_DSHORT, halign = "CENTER"))
  b$push(fmt_table_body(sid, TL_ROW1, TL_ROWD, 1, TL_WN))
  b$push(fmt_row_height(sid, TL_ROWD + 1L, TL_ROWN, 24L))
  b$push(fmt_cells(sid, TL_ROW1, TL_ROWN, 5, 6, numfmt = NF_DSHORT, halign = "LEFT"))
  b$push(fmt_borders(sid, TL_ROW1, TL_ROWD, TL_W1, TL_WN, inner_v = BORDER_SUBTLE))
  # Rules: the first one listed wins per cell (b$cf numbers them 0, 1, 2... for this tab).
  for (s in c("Done", "Blocked", "In progress", "Not started"))       # one bar colour per status
    b$cf(fmt_cond_formula, sid, TL_ROW1, TL_ROWN, TL_W1, TL_WN,
         sprintf('=AND($D5="%s",G$4<=$F5,G$4+6>=$E5)', s), bg_color = ST_COL[[s]])
  # as-of week: the "selected column" look, only on rows that hold a task
  b$cf(fmt_cond_formula, sid, TL_ROW1, TL_ROWN, TL_W1, TL_WN, '=AND($A5<>"",$C$3>=G$4,$C$3<=G$4+6)', bg_color = COL_RAISED)
  b$cf(fmt_cond_formula, sid, TL_HDR, TL_HDR, TL_W1, TL_WN, '=AND($C$3>=G$4,$C$3<=G$4+6)', bg_color = COL_RAISED, font_color = COL_INK)
  b$cf(fmt_cond_formula, sid, TL_ROW1, TL_ROWN, 6, 6, '=AND($A5<>"",$D5<>"Done",$F5<$C$3)', font_color = COL_NEGATIVE, bold = TRUE)
  b$get()
}

# ---- Workload ----------------------------------------------------------------
fmt_workload <- function(sid) {
  b <- new_batch()
  b$push(fmt_tab_base(sid, WL_NOTE + 2L, 13L, "model", widths = c(110, 96, 96, 96, 96, 80, 80, 96, 104, 100, 170), inputs = TRUE))
  b$push(fmt_section(sid, WL_T1_HDR - 1L, 2, 12, numeric_cols = 3:11)); b$push(fmt_row_height(sid, WL_T1_HDR, WL_T1_HDR, 36L))
  b$push(fmt_table_body(sid, WL_T1_ROW1, WL_T1_TOT, 2, 12, numeric_cols = 3:11, total_rows = WL_T1_TOT, total_col = 7,
                        numfmt = c(rep(list(NUMFMT_INT), 8), list(NF_DEC1))))
  b$push(apply_style(sid, WL_T1_ROW1, WL_T1_ROWN, 10, 10, STYLE_INPUT))
  b$push(fmt_section(sid, WL_T2_HDR - 1L, 2, 6, numeric_cols = 3:6)); b$push(fmt_row_height(sid, WL_T2_HDR, WL_T2_HDR, 36L))
  b$push(fmt_table_body(sid, WL_T2_ROW1, WL_T2_TOT, 2, 6, numeric_cols = 3:6, numfmt = NUMFMT_INT,   # whole hours: also the chart's axis format
                        total_rows = WL_T2_TOT, total_col = 6))
  b$push(apply_style(sid, WL_NOTE, WL_NOTE + 1L, 2, 2, STYLE_NOTE))
  for (r in c(5L, WL_T1_TOT + 1L)) b$push(fmt_row_height(sid, r, r, 12L))
  # Rules: the first one listed wins per cell (b$cf numbers them 0, 1, 2... for this tab). Colour only past a limit:
  # red weeks of work (over the overload limit) and red overdue counts; raw hours stay uncoloured.
  b$cf(fmt_cond_formula, sid, WL_T1_ROW1, WL_T1_TOT, 11, 11, sprintf('=AND(ISNUMBER($K%d),$K%d>INDIRECT("%s"))', WL_T1_ROW1, WL_T1_ROW1, OVERLOAD_REF),
       font_color = COL_NEGATIVE, bold = TRUE)
  b$cf(fmt_cond_number, sid, WL_T1_ROW1, WL_T1_ROWN, 8, 8, 0, font_color = COL_NEGATIVE, bold = TRUE)
  b$get()
}

# ---- Command Center ----------------------------------------------------------
fmt_cc <- function(sd) {
  BOX <- list(style = "SOLID_MEDIUM", color = COL_ACCENT)
  b <- new_batch()
  b$push(fmt_tab_base(sd, CC_LAST_ROW, 12L, "dashboard", widths = CC_WIDTHS))
  b$push(apply_style(sd, CTRL[1], CTRL[1], CTRL[2] - 1L, CTRL[2] - 1L, STYLE_NOTE, halign = "RIGHT"))   # "Owner"
  b$push(apply_style(sd, CTRL[1], CTRL[1], CTRL[2], CTRL[2], STYLE_CONTROL, valign = "MIDDLE"))
  b$push(fmt_borders(sd, CTRL[1], CTRL[1], CTRL[2], CTRL[2], top = BOX, bottom = BOX, left = BOX, right = BOX))
  b$push(fmt_dropdown_range(sd, CTRL[1], CTRL[1], CTRL[2], CTRL[2], paste0("=", L_PICK)))
  b$push(fmt_kpi_strip(sd, K_ROW, K_COLS, lead = 2, good = c(rep("none", 5), "down"), rule_end_col = 11,
                       value_numfmt = list(NUMFMT_PCT_WHOLE, NUMFMT_PCT_WHOLE, NUMFMT_INT, NUMFMT_INT, NUMFMT_INT, NF_HRS),
                       delta_numfmt = list(NULL, NULL, NULL, NULL, NULL, NF_VS_PLAN), tol = c(0, 0, 0, 0, 0, 0.5)))
  b$push(apply_style(sd, K_VAL + 2L, K_VAL + 2L, 2, 2, STYLE_NOTE))
  b$push(fmt_section(sd, ST_SEC, 2, 11, header = FALSE, meta_col = 11))
  b$push(fmt_section(sd, BD_SEC, 2, 11, header = FALSE, meta_col = 11))
  b$push(fmt_section(sd, ATT_SEC, 2, 11, numeric_cols = c(6, 8:10)))
  b$push(fmt_cells(sd, ATT_HDR, ATT_HDR, 11, 11, halign = "CENTER"))
  b$push(fmt_table_body(sd, ATT_ROW1, ATT_ROWN, 2, 11, numeric_cols = c(6, 8:10), density = "dashboard",
                        numfmt = list(NF_DSHORT, NUMFMT_PCT_WHOLE, NF_NUM0, NF_NUM0)))
  b$push(fmt_status(sd, ATT_ROW1, ATT_ROWN, 11, 11, c(Overdue = "negative", Blocked = "warning", "At risk" = "warning")))
  b$push(apply_style(sd, ATT_NOTE, ATT_NOTE, 2, 2, STYLE_NOTE))
  b$push(apply_style(sd, ATT_NOTE, ATT_NOTE, 11, 11, STYLE_NOTE, halign = "RIGHT", font_color = COL_ACCENT_700))   # the link
  for (r in c(BD_NOTE, BD_NOTE + 1L)) b$push(apply_style(sd, r, r, 2, 2, STYLE_NOTE))
  b$push(fmt_section(sd, ABOUT, 2, 11, header = FALSE))
  b$push(apply_style(sd, ABOUT + 1L, CC_LAST_ROW, 2, 2, STYLE_BODY, font_color = COL_TEXT_2))
  b$push(fmt_cells(sd, ABOUT + 5L, ABOUT + 6L, 2, 2, font_color = COL_ACCENT_700))    # the two credit links (theme link colour)
  for (rh in list(c(5, 5, 12), c(K_VAL + 2L, ST_SEC - 1L, 20), c(CH_ST, BD_SEC - 2L, 20), c(BD_SEC - 1L, BD_SEC - 1L, 12),
                  c(CH_BD, BD_NOTE + 1L, 20), c(ATT_SEC - 1L, ATT_SEC - 1L, 12), c(ATT_NOTE, ATT_NOTE, 22),
                  c(ABOUT - 1L, ABOUT - 1L, 12), c(ABOUT + 1L, CC_LAST_ROW, 22)))
    b$push(fmt_row_height(sd, rh[1], rh[2], rh[3]))
  # Colour only where there is risk: the overdue and blocked sub-lines when the count is above zero, late days, risk heat.
  b$cf(fmt_cond_formula, sd, K_VAL + 1L, K_VAL + 1L, 4, 4, sprintf("=$%s>0", kv(3)), font_color = COL_NEGATIVE)
  for (k in 4:5) b$cf(fmt_cond_formula, sd, K_VAL + 1L, K_VAL + 1L, K_COLS[k], K_COLS[k], sprintf("=$%s>0", kv(k)), font_color = STATUS$warning$ink)
  b$cf(fmt_cond_number, sd, ATT_ROW1, ATT_ROWN, 9, 9, 0, "less", font_color = COL_NEGATIVE)
  b$cf(fmt_cond_color_scale, sd, ATT_ROW1, ATT_ROWN, 10, 10, SCALE_HEAT$min_color, SCALE_HEAT$mid_color, SCALE_HEAT$max_color)
  b$get()
}

# apply per-tab batches (strict: any API error stops the build with the message)
batch_format(ss, fmt_lists(sid_l), strict = TRUE)
batch_format(ss, fmt_tasks(sid_t), strict = TRUE)
batch_format(ss, fmt_timeline(sid_tl), strict = TRUE)
batch_format(ss, fmt_workload(sid_wl), strict = TRUE)
batch_format(ss, fmt_cc(sid_cc), strict = TRUE)

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: protection, filter views, charts, links (own batches)
# ══════════════════════════════════════════════════════════════════════════════
# ponytail: protection is advisory (warningOnly): enforcing it needs editor emails, which do not belong in a public script
# Whole-sheet protection with an editable hole is the only form the API allows for "protect the formulas, leave the inputs open".
batch_format(ss, list(
  fmt_protected_range(sid_t, T_ROW1, T_AGG, 10, 10, description = "Formula: progress bar"),
  fmt_protected_range(sid_t, T_ROW1, T_AGG, 12, 16, description = "Formulas: hours left, days left, overdue, risk, health"),
  fmt_protected_range(sid_tl, 3, TL_ROWN, 1, TL_WN, description = "Timeline is drawn by formulas from the Tasks tab"),
  fmt_protected_range(sid_wl, description = "Formulas. Only the blue capacity inputs are meant to be edited",
                      unprotected_ranges = grid_range(sid_wl, WL_T1_ROW1, WL_T1_ROWN, 10, 10)),
  fmt_protected_range(sid_cc, description = "Dashboard formulas. Use the Owner picker to filter",
                      unprotected_ranges = grid_range(sid_cc, CTRL[1], CTRL[1], CTRL[2], CTRL[2])),
  fmt_protected_range(sid_l, BD_HDR, BD_WK_LAST, 1, 13, description = "Chart data (formulas)"),
  fmt_protected_range(sid_l, 8, 8, 2, 2, description = "Formula"),
  fmt_protected_range(sid_l, 13, 19, 6, 6, description = "Formulas")), strict = TRUE)

# Owner slicer chip on the Tasks tab. A slicer only filters rows (and charts built on its own data range), so it would not
# move the Command Center KPIs and charts, which are formulas: the Owner picker drives those instead.
batch_format(ss, list(fmt_slicer(sid_t, sid_t, c(T_HDR, T_ROWN, 1L, 16L), column_index = TC$owner - 1L, anchor_row = 1L,
                                 anchor_col = 11L, title = "Owner", size = c(250L, 34L))), strict = TRUE)

# All four saved views share one sort: risk score, high to low. They run to the last formula row (T_AGG) so new tasks are included;
# the empty-string rows would sort first in a descending sort, so every view hides the rows with no ID.
fv <- function(title, criteria = list())
  fmt_filter_view(sid_t, T_HDR, T_AGG, 1, 16, title, criteria = c(list("0" = list(condition = list(type = "NOT_BLANK"))), criteria),
                  sort_specs = list(list(dimensionIndex = 14L, sortOrder = "DESCENDING")))
batch_format(ss, list(
  fv("Needs attention (open, by risk)", list("15" = list(hiddenValues = list("Done", "On track")))),
  fv("Blocked or overdue", list("15" = list(hiddenValues = list("Done", "On track", "At risk")))),
  fv("P0 and P1 only", list("4" = list(hiddenValues = list("P2", "P3")))),
  fv(paste("Only", OWNERS[1]), list("3" = list(hiddenValues = as.list(setdiff(OWNERS, OWNERS[1])))))), strict = TRUE)

# Charts read their data from Lists and sit on the Command Center (anchor_sheet_id), filling B..K (CC_W px). Status is a
# breakdown of states, so it is a 100% bar, never a pie: one accent family (not started, in progress), the warning mark on
# Blocked, grey for Done. The titles stay descriptive because the owner picker changes the data under them.
st_label <- function(s) list(type = "DATA", placement = "CENTER",
  textFormat = list(fontSize = 9, foregroundColorStyle = list(rgbColor = if (s == "In progress") COL_WHITE else COL_INK)))
st_series <- function(r1, r2) lapply(5:8, function(cc) { s <- STATUSES[cc - 4L]
  list(range = c(r1, r2, cc, cc), color = ST_COL[[s]], label = st_label(s)) })
status_bar <- fmt_chart_bar(sid_l, "Tasks by status", domain_range = c(ST_HDR, ST_ROW, 4, 4), series_list = st_series(ST_HDR, ST_ROW),
  header_count = 1L, stacked_type = "PERCENT_STACKED", legend = "TOP_LEGEND", anchor = c(CH_ST, 2L), size = c(CC_W, 152L),
  anchor_sheet_id = sid_cc, x_title = "Share of the tasks in view", offset_y = 4L, style = STYLE_CHART)
ws_bar <- fmt_chart_bar(sid_l, "Tasks by workstream and status", domain_range = c(BD_HDR, BD_ROW1 + 4L, 4, 4),
  series_list = st_series(BD_HDR, BD_ROW1 + 4L), header_count = 1L, stacked_type = "STACKED", legend = "TOP_LEGEND",
  anchor = c(CH_WS, 2L), size = c(CC_W, 252L), anchor_sheet_id = sid_cc, x_title = "Tasks", offset_y = 4L, style = STYLE_CHART)
burn <- fmt_chart_basic(sid_l, "Hours remaining, planned vs actual", "LINE",
  domain_range = c(BD_HDR, BD_WK_LAST, 11, 11),
  series_list = list(list(range = c(BD_HDR, BD_WK_LAST, 12, 12), color = GREY, line = list(width = 2, type = "MEDIUM_DASHED")),
                     list(range = c(BD_HDR, BD_WK_LAST, 13, 13), color = COL_ACCENT, line = list(width = 3))),
  header_count = 1L, anchor = c(CH_BD, 2L), size = c(CC_W, 312L), legend = "TOP_LEGEND",
  anchor_sheet_id = sid_cc, x_title = "Week starting", y_title = "Hours remaining", offset_y = 4L, style = STYLE_CHART)
batch_format(ss, list(status_bar, ws_bar, burn), strict = TRUE)
batch_format(ss, list(fmt_chart_basic(sid_wl, TTL_WL, "COLUMN",
  domain_range = c(WL_T2_HDR, WL_T2_ROWN, 2, 2),
  series_list = lapply(3:5, function(cc) list(range = c(WL_T2_HDR, WL_T2_ROWN, cc, cc), color = ST_COL[[STATUSES[cc - 2L]]])),
  header_count = 1L, stacked_type = "STACKED", anchor = c(WL_T2_HDR - 1L, 8L), size = c(550L, 300L), legend = "TOP_LEGEND",   # H..L = 550 px: flush with the table above
  y_title = "Hours left", style = STYLE_CHART)), strict = TRUE)

# Rich-text links and the note go in their own last batch
tasks_url <- sprintf("https://docs.google.com/spreadsheets/d/%s/edit#gid=%d", ss_id, sid_t)
# Only Tasks!O3 gets a note: Sheets' PDF export prints every note as a [n] marker plus an extra page, and on the Command Center
# the risk definition is visible text instead.
batch_format(ss, list(
  link_cells_req(sid_cc, ATT_NOTE, 11, "Open the full task list", tasks_url),
  link_cells_req(sid_cc, ABOUT + 5L, 2, c("Built with the r-googlesheets4 skill (github.com/salvadoraveldano/r-googlesheets4)",
                                          "Built on googlesheets4 by Jennifer Bryan and Posit (googlesheets4.tidyverse.org)"),
                 c(REPO_URL, GS4_URL)),
  fmt_note(sid_t, 3, 15, sprintf(paste0("Risk score, 0 to 100 (Done tasks score 0): priority points + schedule-gap points + an overdue bonus + a blocked bonus, ",
    "capped at 100. The weights are inputs on the Lists tab, rows %d to %d. At or above the At-risk threshold (Lists!B%d) the task is flagged At risk."),
    LW1, LW1 + 3L, THR_ROW))), strict = TRUE)

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: post-build QA (reads the live sheet back and checks it against the R reference)
# ══════════════════════════════════════════════════════════════════════════════
Sys.sleep(4)
sheet_url <- sprintf("https://docs.google.com/spreadsheets/d/%s", ss_id)
problems <- character()
bad <- function(...) problems <<- c(problems, sprintf(...))

# 1. no error values anywhere
err_re <- "^#(REF|DIV/0|NAME|N/A|VALUE|NUM|NULL|ERROR)|^Err:|###"
scan_ranges <- c(sprintf("'%s'!A1:L%d", TAB_CC, CC_LAST_ROW), sprintf("'%s'!A1:P%d", TAB_TASKS, T_AGG),
                 sprintf("'%s'!A1:V%d", TAB_TL, TL_ROWN), sprintf("'%s'!A1:M%d", TAB_WL, WL_NOTE + 1L), sprintf("'%s'!A1:M%d", TAB_LISTS, WLD_LAST + 4L))
fv_all <- read_values(ss, scan_ranges)
for (i in seq_along(fv_all)) {
  hits <- sum(grepl(err_re, fv_all[[i]]))
  if (hits) bad("%d error value(s) in %s", hits, scan_ranges[i])
}

# 2. formulas agree with the R reference (all people, then one owner)
check_view <- function(owner) {
  e <- expected(tk, owner); b <- burn_expected(tk, owner)
  v <- read_values(ss, c(sprintf("'%s'!%s:%s", TAB_CC, kv(1), kv(6)), sprintf("'%s'!J%d:M%d", TAB_LISTS, BD_ROW1, BD_WK_LAST),
                         sprintf("'%s'!B4", TAB_CC)), "UNFORMATTED_VALUE")
  k <- suppressWarnings(as.numeric(v[[1]])); bl <- v[[2]]      # B..I: on track, done, overdue, blocked, at risk, (G, H empty), hours
  n_meta <- as.numeric(sub("^.*? · ([0-9]+) tasks? .*$", "\\1", v[[3]][1, 1], perl = TRUE))   # the tasks count in the B4 meta line
  got <- c(total = n_meta, done = k[2], over = k[3], blocked = k[4], atrisk = k[5], hours = k[8], ontrack = k[1])
  want <- c(total = e$total, done = e$done / e$total, over = e$over, blocked = e$blocked, atrisk = sum(e$health == "At risk"),
            hours = e$hours, ontrack = e$ontrack)
  lab <- owner %||% ALL_LABEL
  for (nm in names(want)) if (!isTRUE(all.equal(as.numeric(got[[nm]]), as.numeric(want[[nm]]), tolerance = 1e-6)))
    bad("[%s] KPI %s: sheet %s vs expected %s", lab, nm, got[[nm]], want[[nm]])
  planned <- as.numeric(bl[, 3]); actual <- suppressWarnings(as.numeric(bl[, 4]))   # actual is blank after the as-of week
  if (!isTRUE(all.equal(planned, b$planned, tolerance = 1e-6))) bad("[%s] planned burn differs", lab)
  if (!isTRUE(all.equal(actual[!is.na(actual)], b$actual, tolerance = 1e-6))) bad("[%s] actual burn differs", lab)
  if (sum(!is.na(actual)) != length(b$actual)) bad("[%s] actual has %d points, expected %d", lab, sum(!is.na(actual)), length(b$actual))
}
set_picker <- function(who) {
  write_cell(ss, TAB_CC, CTRL[1], CTRL[2], who); flush_writes(ss, strict = TRUE); Sys.sleep(3)
}
set_picker(ALL_LABEL); check_view(NULL)
set_picker(OWNERS[2]); check_view(OWNERS[2])
set_picker("")                                          # a cleared picker must behave exactly like All people
check_view(NULL)
cap <- read_values(ss, sprintf("'%s'!B4", TAB_CC))[[1]][1, 1]
if (!grepl(" tasks across ", cap)) bad("blank picker: meta line reads '%s', expected the All people one", cap)
set_picker(ALL_LABEL)

# the guarded rows below the sample tasks must stay empty, and the headline cells must read well
spare <- as.vector(read_values(ss, sprintf("'%s'!J%d:P%d", TAB_TASKS, T_ROWN + 1L, T_AGG))[[1]])
if (any(nzchar(spare))) bad("%d non-empty cell(s) in the guarded Tasks rows %d-%d", sum(nzchar(spare)), T_ROWN + 1L, T_AGG)
for (a1 in c("B2", "B3", sprintf("K%d", ST_SEC), sprintf("K%d", BD_SEC))) message(sprintf("[headline] %s = %s", a1,
  read_values(ss, sprintf("'%s'!%s", TAB_CC, a1))[[1]][1, 1]))

hv <- read_values(ss, sprintf("'%s'!L%d:P%d", TAB_TASKS, T_ROW1, T_ROWN), "UNFORMATTED_VALUE")[[1]]   # L..P: hours left .. health
got_health <- hv[, 5]; got_risk <- as.numeric(hv[, 4])
if (!identical(got_health, EXP$health)) bad("Tasks health differs from reference in %d row(s)", sum(got_health != EXP$health))
if (!isTRUE(all.equal(got_risk, EXP$risk))) bad("Tasks risk differs from reference in %d row(s)", sum(got_risk != EXP$risk))

# 3. charts exist and read from visible cells
n_charts <- sum(gs_count_objects(ss_id)$charts)
if (n_charts != 4L) bad("expected 4 charts, found %d", n_charts)
src <- audit_chart_sources(ss_id)                        # every tab, including charts that sit on a different tab than their data
if (length(src)) bad("chart source audit: %s", paste(src, collapse = "; "))

# 4. on-screen layout audit (truncation, ###, thin columns, contrast)
lay <- do.call(rbind, lapply(TABS, function(t) audit_layout(ss, t)))
message(sprintf("[audit_layout] %d finding(s): %d blocker, %d major, %d minor", nrow(lay),
                sum(lay$severity == "blocker"), sum(lay$severity == "major"), sum(lay$severity == "minor")))
if (nrow(lay)) print(as.data.frame(lay[lay$severity != "minor", ]), row.names = FALSE)
if (any(lay$severity == "blocker")) bad("layout audit has %d blocker(s)", sum(lay$severity == "blocker"))
if (nzchar(QA_DIR)) { qa <- visual_qa(ss, out_dir = QA_DIR); print(unlist(qa$pages)) }

if (length(problems)) stop("QA failed:\n  - ", paste(problems, collapse = "\n  - "), call. = FALSE)
cat("QA passed: no errors, formulas match the R reference, 4 charts, layout clean\n")
cat("Sheet URL:", sheet_url, "\n")
