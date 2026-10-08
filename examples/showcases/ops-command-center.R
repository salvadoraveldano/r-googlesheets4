# =============================================================================
# ops-command-center.R - "Ops Command Center - Sample Data" showcase sheet
# =============================================================================
# Builds: a five-tab project / ops dashboard in Google Sheets from synthetic data.
#   Command Center  KPI cards, one-line top-risk takeaway, status doughnut, workstream stacked bar, burn-down
#                   (planned vs actual), top-5 "needs attention" list, owner picker
#   Tasks           45 tasks, dropdowns, banding, filter, sparkline progress bars,
#                   formula columns (days left, overdue, risk score, health) ready down to row 120
#   Timeline        weekly Gantt grid drawn by conditional formatting from formulas
#   Workload        owner x status counts and hours with heatmaps, capacity inputs
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
SEL <- "'Command Center'!$K$2"                              # owner picker cell (blank counts as "All people", see Lists!B8)
OWN_SCOPE <- sprintf('((%s=%s)+(%s="*")>0)', tr("owner"), CRIT, CRIT)     # CRIT is "*" for everyone, else the owner's name
# COUNTIFS / SUMIFS criteria for the same view. "*" matches text only, so a task with a blank owner would drop out of All people
# (OWN_SCOPE above, in array formulas, already keeps it): count by ID instead, and let everyone be "anything but (all)".
IN_VIEW <- sprintf('%s,"<>",%s,IF(%s="*","<>(all)",%s)', tr("id"), tr("owner"), CRIT, CRIT)
LW_BAR <- 41L; LW1 <- 42L; LW_DEF <- LW1 + length(RISK_W)                  # Lists: "How risk is scored" block (bar, 4 weights, definition)
WLD_BAR <- LW_DEF + 2L; WLD1 <- WLD_BAR + 1L; WLD_LAST <- WLD1 + 1L        # Lists: "Workload limits" block (bar, overload weeks, load bar scale)
OVERLOAD_REF <- sprintf("Lists!$B$%d", WLD1); LOADBAR_REF <- sprintf("Lists!$B$%d", WLD1 + 1L)
W_REF <- sprintf("Lists!$B$%d", LW1 + 0:3)                                 # points per priority weight, gap, overdue, blocked
names(W_REF) <- names(RISK_W)
BD_HDR <- 22L; BD_ROW1 <- 23L; BD_WK_N <- 17L; BD_WK_LAST <- BD_ROW1 + BD_WK_N - 1L   # chart data on Lists
TL_HDR <- 4L; TL_ROW1 <- 5L; TL_ROWD <- TL_ROW1 + n - 1L; TL_ROWN <- T_AGG + 1L   # Timeline row = Tasks row + 1; TL_ROWD = last sample task
TL_W1 <- 7L; TL_WN <- TL_W1 + N_WEEKS - 1L
WL_T1_HDR <- 5L; WL_T1_ROW1 <- 6L; WL_T1_ROWN <- WL_T1_ROW1 + length(OWNERS) - 1L; WL_T1_TOT <- WL_T1_ROWN + 1L
WL_T2_HDR <- 16L; WL_T2_ROW1 <- 17L; WL_T2_ROWN <- WL_T2_ROW1 + length(OWNERS) - 1L; WL_T2_TOT <- WL_T2_ROWN + 1L
CC_LAST_ROW <- 57L
CC_COLW <- 82L; CC_W <- 12L * CC_COLW; CC_GAP <- 12L        # Command Center: columns B..M are 984 px wide; the two top charts share it
CC_HALF <- (CC_W - CC_GAP) %/% 2L                           # 486 px each
CC_BAR_DX <- CC_HALF + CC_GAP - 6L * CC_COLW                # right chart starts in column H (6 columns in), nudged so the gap is CC_GAP

# ── Palette ──────────────────────────────────────────────────────────────────
ST_HEX    <- c("Not started" = "9DB0D3", "In progress" = "2457C5", "Blocked" = "F5A524", "Done" = "18A957")
C_SLATE   <- hex_to_color("4A5568"); C_INPUT <- hex_to_color("1F4FBF"); C_INPUT_BG <- hex_to_color("FFF8DC")
C_BAND    <- hex_to_color("F5F7FB"); C_GRID  <- hex_to_color("DDE3EE"); C_CARD <- hex_to_color("F1F5FD")
C_RED_BG  <- hex_to_color("FDECEC"); C_AMB_BG <- hex_to_color("FEF4E6"); C_AMB_FG <- hex_to_color("9A5B00")
C_GRN_BG  <- hex_to_color("E7F6EE"); C_GRN_FG <- hex_to_color("14804A"); C_GREY_FG <- hex_to_color("5F6B7A")
C_GREY_BG <- hex_to_color("EEF0F4"); C_RISK_BG <- hex_to_color("FFF3D6"); C_RISK_FG <- hex_to_color("B45309")
C_ASOF    <- hex_to_color("FFF3D6")
NF_DATE <- list(type = "DATE", pattern = "mmm d, yyyy"); NF_DSHORT <- list(type = "DATE", pattern = "mmm d")
NF_DEC1 <- list(type = "NUMBER", pattern = "#,##0.0"); NF_NUM0 <- list(type = "NUMBER", pattern = "0")
NF_HRS  <- list(type = "NUMBER", pattern = '#,##0" h"')

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

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: buffer every cell write (values and formulas), then flush once
# ══════════════════════════════════════════════════════════════════════════════

# ---- Lists -------------------------------------------------------------------
write_cell(ss, TAB_LISTS, 1, 1, "Lists and settings")
write_cell(ss, TAB_LISTS, 2, 1, paste0("Sample data. Blue-on-yellow cells are inputs: dates, threshold, risk weights, priority weights, workload limits. Grey lists feed the dropdowns; ",
  "their names are matched exactly by the formulas and by the Tasks rows, so rename one only together with the Tasks column."))
write_cell(ss, TAB_LISTS, 4, 1, "SETTINGS")
write_cell(ss, TAB_LISTS, 5, 1, "As-of date");                  write_cell(ss, TAB_LISTS, 5, 2, format(ASOF))
write_cell(ss, TAB_LISTS, 5, 3, "Fixed so this sample never changes. To make the sheet live, replace this cell with =TODAY().")
write_cell(ss, TAB_LISTS, 6, 1, "Timeline start (a Monday)");   write_cell(ss, TAB_LISTS, 6, 2, format(START))
write_cell(ss, TAB_LISTS, 6, 3, "First week on the Timeline and the burn-down chart.")
write_cell(ss, TAB_LISTS, THR_ROW, 1, "At-risk threshold");     write_cell(ss, TAB_LISTS, THR_ROW, 2, RISK_THRESHOLD)
write_cell(ss, TAB_LISTS, THR_ROW, 3, sprintf("An open task with a risk score at or above this is flagged At risk. The score is defined in HOW RISK IS SCORED, row %d.", LW_BAR))
write_cell(ss, TAB_LISTS, 8, 1, "Owner criterion (formula)")
write_cell(ss, TAB_LISTS, 8, 2, sprintf('=IF(OR(%s="",%s="%s"),"*",%s)', SEL, SEL, ALL_LABEL, SEL))
write_cell(ss, TAB_LISTS, 8, 3, "Driven by the Owner view picker on the Command Center. A blank picker counts as All people.")
write_cell(ss, TAB_LISTS, 10, 1, "DROPDOWN SOURCES")
write_block(ss, TAB_LISTS, 11, 1, rbind(c("Status", "Priority", "Priority weight", "Owner", "Workstream", "Owner view options")))
write_block(ss, TAB_LISTS, 12, 1, matrix(STATUSES, ncol = 1))
write_block(ss, TAB_LISTS, 12, 2, data.frame(PRIORITIES, PRIO_W))        # data.frame keeps the weights numeric
write_block(ss, TAB_LISTS, 12, 4, matrix(OWNERS, ncol = 1))
write_block(ss, TAB_LISTS, 12, 5, matrix(WORKSTREAMS, ncol = 1))
write_cell(ss, TAB_LISTS, 12, 6, ALL_LABEL)
write_block(ss, TAB_LISTS, 13, 6, matrix(sprintf("=D%d", 12:18), ncol = 1))
write_cell(ss, TAB_LISTS, 20, 1, sprintf("The lists hold %d owners and %d workstreams, set in the build script (OWNERS, WORKSTREAMS): adding one means editing the script and rerunning it.",
                                         length(OWNERS), length(WORKSTREAMS)))
write_cell(ss, TAB_LISTS, 21, 1, "CHART DATA (formulas, do not edit)")
write_block(ss, TAB_LISTS, BD_HDR, 1, rbind(c("Status (count)", "Tasks")))
# The doughnut has no slice labels in the API, so its legend label carries the live count: "Done  (14)"
write_block(ss, TAB_LISTS, BD_ROW1, 1, cbind(sprintf('=A%d&"  ("&B%d&")"', 12:15, BD_ROW1:(BD_ROW1 + 3L)),
  sprintf('=COUNTIFS(%s,A%d,%s)', tr("status"), 12:15, IN_VIEW)))
write_block(ss, TAB_LISTS, BD_HDR, 4, rbind(c("Workstream", sprintf("=A%d", 12:15))))
ws_rows <- BD_ROW1:(BD_ROW1 + length(WORKSTREAMS) - 1L)
write_block(ss, TAB_LISTS, BD_ROW1, 4, cbind(sprintf("=E%d", 12:16), sapply(5:8, function(cc)
  sprintf('=COUNTIFS(%s,$D%d,%s,%s$%d,%s)', tr("ws"), ws_rows, tr("status"), col_letter(cc), BD_HDR, IN_VIEW))))
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
write_cell(ss, TAB_LISTS, LW_BAR, 1, "HOW RISK IS SCORED (0 to 100)")
write_block(ss, TAB_LISTS, LW1, 1, data.frame(
  c("Points per priority weight", "Schedule-gap weight", "Overdue bonus", "Blocked bonus"), unname(RISK_W),
  c("Priority points = this x the Priority weight in the table above.",
    "Points when progress trails the elapsed share of the schedule by 100% (scaled down proportionally).",
    "Added to an open task that is past its due date.",
    "Added to a task whose status is Blocked.")))
write_cell(ss, TAB_LISTS, LW_DEF, 1, paste0("Risk score = priority points + schedule-gap points + overdue bonus + blocked bonus, capped at 100. ",
  sprintf("Done tasks score 0. At or above the At-risk threshold (row %d) a task is flagged At risk.", THR_ROW)))

# Workload limits: the two numbers the Workload tab reads (inputs)
write_cell(ss, TAB_LISTS, WLD_BAR, 1, "WORKLOAD LIMITS")
write_block(ss, TAB_LISTS, WLD1, 1, data.frame(
  c("Overload above (weeks)", "Load bar full at (weeks)"), c(OVERLOAD_WEEKS, LOAD_BAR_WEEKS),
  c("A person whose hours left need more weeks than this turns red on the Workload tab (number and bar).",
    "The Workload load bar is full at this many weeks of work. Keep it above the overload limit.")))

# ---- Tasks -------------------------------------------------------------------
write_cell(ss, TAB_TASKS, 1, 1, "Tasks (sample data)")
write_cell(ss, TAB_TASKS, 2, 1, "Input")
write_cell(ss, TAB_TASKS, 2, 2, paste0("Blue text is an input you can edit. Black text is a formula (editing it shows a warning). Slate headers are formula columns. ",
  "Done rows turn grey. To add a task, type an ID and its inputs in the next empty row: the formulas are ready down to row ", T_AGG, "."))
hdr_tasks <- c("ID", "Task", "Workstream", "Owner", "Priority", "Status", "Start", "Due", "% done", "Progress",
               "Est. hours", "Hours left", "Days left", "Overdue", "Risk score", "Health")
write_block(ss, TAB_TASKS, T_HDR, 1, rbind(hdr_tasks))
write_block(ss, TAB_TASKS, T_ROW1, 1, data.frame(tk$id, tk$task, tk$workstream, tk$owner, tk$priority, tk$status,
                                              format(tk$start), format(tk$due), tk$pct))
write_block(ss, TAB_TASKS, T_ROW1, 11, matrix(tk$est, ncol = 1))
rf <- T_ROW1:T_AGG                                      # formula rows: the sample tasks plus the empty rows ready for new ones
guard <- function(f) paste0('=IF($A', rf, '="","",', f, ')')   # empty ID -> empty row (no false "Overdue", no negative days)
bar_f <- vapply(rf, function(r) fraw(f_sparkline(sprintf("{I%d,1-I%d}", r, r), list(charttype = "bar",
  color1 = I(sprintf('IF(F%d="Done","#18A957",IF(F%d="Blocked","#F5A524","#2457C5"))', r, r)), color2 = "#E3E8F2"))), "")
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
write_cell(ss, TAB_TL, 2, 1, "Weekly Gantt view. Bars are drawn by conditional formatting from each task's start and due dates, colored by status. The amber column is the as-of week.")
write_cell(ss, TAB_TL, 3, 2, "As-of date (from Lists)")
write_cell(ss, TAB_TL, 3, 3, sprintf("=%s", ASOF_REF))
TL_KEY <- TL_WN - 7L                                    # colour key: four 2-column chips on row 2, right-aligned to the grid
for (i in seq_along(STATUSES)) write_cell(ss, TAB_TL, 2, TL_KEY + 2L * (i - 1L), STATUSES[i])
write_block(ss, TAB_TL, TL_HDR, 1, rbind(c("ID", "Task", "Owner", "Status", "Start", "Due")))
write_cell(ss, TAB_TL, TL_HDR, TL_W1, sprintf("=%s", START_REF))
write_block(ss, TAB_TL, TL_HDR, TL_W1 + 1L, rbind(sprintf("=%s4+7", sapply(TL_W1:(TL_WN - 1L), col_letter))))
write_block(ss, TAB_TL, 3, TL_W1, rbind(sprintf('=IF(AND($C$3>=%s$4,$C$3<=%s$4+6),"▼","")',
                                            sapply(TL_W1:TL_WN, col_letter), sapply(TL_W1:TL_WN, col_letter))))
tcols <- c("A", "B", "D", "F", "G", "H")
write_block(ss, TAB_TL, TL_ROW1, 1, sapply(tcols, function(cl) sprintf('=IF(Tasks!$A%d="","",Tasks!%s%d)', rf, cl, rf)))

# ---- Workload ----------------------------------------------------------------
write_cell(ss, TAB_WL, 1, 2, "Workload (sample data)")
write_cell(ss, TAB_WL, 2, 2, "Who is carrying what. Everything is a formula on the Tasks tab except the blue capacity inputs.")
write_cell(ss, TAB_WL, 4, 2, "TASKS BY OWNER AND STATUS")
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
    color1 = I(sprintf('IF(K%d>%s,"#E5484D","#2457C5")', rr, OVERLOAD_REF)), color2 = "#E3E8F2"), iferror = TRUE), "")))
write_block(ss, TAB_WL, WL_T1_TOT, 2, rbind(c("Total",
  sapply(3:10, function(cc) sprintf("=SUM(%s%d:%s%d)", col_letter(cc), WL_T1_ROW1, col_letter(cc), WL_T1_ROWN)),
  f_safe_div(sprintf("I%d", WL_T1_TOT), sprintf("J%d", WL_T1_TOT)), NA)))
write_cell(ss, TAB_WL, WL_T2_HDR - 1L, 2, "HOURS REMAINING BY OWNER AND STATUS")
write_block(ss, TAB_WL, WL_T2_HDR, 2, rbind(c("Owner", sprintf("=Lists!$A$%d", 12:14), "Total")))
ow2 <- WL_T2_ROW1:WL_T2_ROWN
write_block(ss, TAB_WL, WL_T2_ROW1, 2, cbind(
  sprintf("=$B%d", ow_r),
  sapply(3:5, function(cc) sprintf('=SUMIFS(%s,%s,$B%d,%s,%s$%d)', tr("left"), tr("owner"), ow2, tr("status"), col_letter(cc), WL_T2_HDR)),
  sprintf("=SUM(C%d:E%d)", ow2, ow2)))
write_block(ss, TAB_WL, WL_T2_TOT, 2, rbind(c("Total", sapply(3:6, function(cc)
  sprintf("=SUM(%s%d:%s%d)", col_letter(cc), WL_T2_ROW1, col_letter(cc), WL_T2_ROWN)))))
write_cell(ss, TAB_WL, WL_T2_TOT + 2L, 2, sprintf(paste0('="Capacity is an input. Weeks of work = hours left / capacity; more than "&%s&" weeks turns red ',
  '(number and bar, total row included; the limit is an input on Lists). Done tasks carry no hours. Tasks with no owner count on the Command Center only."'), OVERLOAD_REF))

# ---- Command Center ----------------------------------------------------------
write_cell(ss, TAB_CC, 1, 2, "Ops Command Center - Sample Data")
write_cell(ss, TAB_CC, 2, 2, sprintf('="Sample data  |  as of "&TEXT(%s,"mmm d, yyyy")&"  |  every number is a live formula"', ASOF_REF))
write_cell(ss, TAB_CC, 1, 11, "Built with r-googlesheets4")     # becomes a link chip in the last batch
write_cell(ss, TAB_CC, 2, 9, "Pick owner view")
write_cell(ss, TAB_CC, 2, 11, ALL_LABEL)
cnt_status <- function(s) sprintf('COUNTIFS(%s,%s,"%s")', IN_VIEW, tr("status"), s)
kpi_labels <- c("TOTAL TASKS", "% DONE", "OVERDUE", "BLOCKED", "HOURS REMAINING", "ON TRACK")
kpi_cols   <- seq(2L, 12L, by = 2L)
kpi_vals <- c(
  sprintf("=COUNTIFS(%s)", IN_VIEW),
  f_safe_div(cnt_status("Done"), "B5"),
  sprintf('=COUNTIFS(%s,%s,"Overdue")', IN_VIEW, tr("over")),
  sprintf("=%s", cnt_status("Blocked")),
  sprintf("=SUMIFS(%s,%s)", tr("left"), IN_VIEW),
  f_safe_div(sprintf('(COUNTIFS(%s,%s,"On track")+%s)', IN_VIEW, tr("health"), cnt_status("Done")), "B5"))
kpi_caps <- c(
  sprintf('=IF(%s="*","across "&COUNTA(%s)&" people","assigned to "&%s)', CRIT, L_OWNER, CRIT),
  sprintf('=%s&" of "&B5&" tasks"', cnt_status("Done")),
  # Blocked wins over Overdue in the Health column, so a task that is both is counted in both cards: say so
  sprintf('=IF(%1$s>0,"past due, "&%1$s&" also blocked","past due and not done")',
          sprintf('COUNTIFS(%s,%s,"Overdue",%s,"Blocked")', IN_VIEW, tr("over"), tr("status"))),
  "waiting on a dependency",
  sprintf('="of "&TEXT(SUMIFS(%s,%s),"#,##0")&" h estimated"', tr("est"), IN_VIEW),
  "done or on schedule")
for (k in 1:6) {
  write_cell(ss, TAB_CC, 4, kpi_cols[k], kpi_labels[k]); write_cell(ss, TAB_CC, 5, kpi_cols[k], kpi_vals[k])
  write_cell(ss, TAB_CC, 6, kpi_cols[k], kpi_caps[k])
}
# One-line takeaway under the cards: reads the top row of the Needs-attention table (row 47) and the KPI cells F5 / H5
write_cell(ss, TAB_CC, 7, 2, sprintf(paste0('=IF(C47="","No open tasks in this view.",IF(AND(K47<%s,F5+H5=0),',
  '"Nothing at risk in this view: the highest risk score is "&K47&"/100 (flagged from "&%s&"), nothing overdue or blocked",',
  '"Top risk right now: "&C47&" ("&B47&"), owner "&IF(I47="","(none)",I47)&", risk score "&K47&"/100   |   "&F5&" overdue   |   "&H5&" blocked"))'),
  THR_REF, THR_REF))
write_cell(ss, TAB_CC, 8, 2, '="STATUS AND WORKSTREAMS   |   "&B5&IF(B5=1," task"," tasks")&" in view"')
# Burn-down verdict: last actual point (week start on or before the as-of date) against the plan for the same week
bd_col <- function(cl) sprintf("Lists!$%s$%d:$%s$%d", cl, BD_ROW1, cl, BD_WK_LAST)
write_cell(ss, TAB_CC, 26, 2, sprintf(paste0('=LET(k,COUNT(%s),"BURN-DOWN: HOURS REMAINING, PLANNED VS ACTUAL"&IF(k=0,"",',
  'LET(x,INDEX(%s,k)-INDEX(%s,k),"   |   "&IF(ROUND(x,0)>0,"Behind plan by "&TEXT(x,"#,##0")&" h",',
  'IF(ROUND(x,0)<0,"Ahead of plan by "&TEXT(-x,"#,##0")&" h","On plan"))&" at "&TEXT(INDEX(%s,k),"mmm d"))))'),
  bd_col("M"), bd_col("M"), bd_col("L"), bd_col("J")))
write_cell(ss, TAB_CC, 43, 2, paste0("Planned = straight-line plan between each task's start and due date. Actual = hours left, reconstructed ",
  "by assuming steady progress from each task's start to its current % complete. The actual line stops at the as-of week."))
write_cell(ss, TAB_CC, 45, 2, "NEEDS ATTENTION: TOP 5 OPEN TASKS BY RISK SCORE")
write_block(ss, TAB_CC, 46, 2, rbind(c("ID", "Task", NA, NA, NA, "Workstream", NA, "Owner", "Due", "Risk", "Health")))
att_formula <- function(i, col) sprintf(paste0('=IFERROR(INDEX(SORT(FILTER(Tasks!$A$%d:$P$%d,%s<>"",%s<>"Done",%s),15,FALSE,8,TRUE),%d,%d),"")'),
                                        T_ROW1, T_AGG, tr("id"), tr("status"), OWN_SCOPE, i, col)
for (i in 1:5) for (cc in list(c(2, 1), c(3, 2), c(7, 3), c(9, 4), c(10, 8), c(11, 15), c(12, 16)))
  write_cell(ss, TAB_CC, 46 + i, cc[1], att_formula(i, cc[2]))
write_cell(ss, TAB_CC, 52, 2, sprintf("Risk score 0-100 = priority + schedule gap + overdue and blocked bonuses (weights on Lists, row %d).", LW_BAR))
write_cell(ss, TAB_CC, 52, 10, "Open the full task list")         # becomes a link in the last batch
write_cell(ss, TAB_CC, 53, 2, "ABOUT THIS SAMPLE")
write_cell(ss, TAB_CC, 54, 2, paste0("Every name, task, date and hour here is synthetic, generated in R with a fixed random seed. ",
  "Pick a person in Owner view to filter this page, or edit the blue inputs on the Tasks tab (it also has an Owner slicer and saved ",
  "views under Data > Filter views) and everything recalculates. To add a task, fill the next empty row on Tasks: its formulas are ready. ",
  sprintf("The Tasks filter and Owner slicer stop at row %d, so widen them (Data > Create a filter) after adding rows; the saved views already cover them.", T_ROWN)))

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: flush, then one formatting batch per tab
# ══════════════════════════════════════════════════════════════════════════════
flush_writes(ss, strict = TRUE)
Sys.sleep(4)

# This sheet's style vocabulary (body, title, header band, section bar, input and fixed cells): thin presets over the skill's
# apply_style() / fmt_cells() so every tab reads the same. Showcase look, not a skill gap.
body_fmt <- function(sid, rows, cols, size = 10) apply_style(sid, 1, rows, 1, cols, STYLE_BODY, font_size = size)
title_fmt <- function(sid, r, c) apply_style(sid, r, r, c, c, STYLE_BRAND_TITLE, font_size = 20)
sub_fmt   <- function(sid, r, c) apply_style(sid, r, r, c, c, STYLE_SUBTITLE, font_size = 10, wrap = FALSE)
band_hdr  <- function(sid, r, c1, c2, bg = COL_BRAND, size = 10)
  apply_style(sid, r, r, c1, c2, STYLE_BODY_BOLD, font_size = size, font_color = COL_WHITE, bg_color = bg, halign = "CENTER", wrap = TRUE)
section_bar <- function(sid, r, c1, c2)
  c(list(apply_style(sid, r, r, c1, c2, STYLE_BODY_BOLD, font_size = 11, font_color = COL_WHITE, bg_color = COL_BRAND, halign = "LEFT"),
         fmt_row_height(sid, r, r, 26L)))
input_cell <- function(sid, r1, r2, c1, c2, ...) fmt_cells(sid, r1, r2, c1, c2, font_color = C_INPUT, bg_color = C_INPUT_BG, ...)
fixed_cell <- function(sid, r1, r2, c1, c2, ...) fmt_cells(sid, r1, r2, c1, c2, font_color = C_GREY_FG, bg_color = C_GREY_BG, ...)
thin <- list(style = "SOLID", color = C_GRID)

# ---- Lists -------------------------------------------------------------------
fmt_lists <- function(sid) {
  c(list(fmt_gridlines(sid, TRUE), fmt_freeze(sid, rows = 2L), fmt_tab_color(sid, hex_to_color("9AA5B8"))),
    fmt_col_widths(sid, c(215, 130, 130, 150, 130, 150, 100, 100, 30, 100, 80, 90, 120)),
    list(body_fmt(sid, 60L, 13), title_fmt(sid, 1, 1), sub_fmt(sid, 2, 1), fmt_row_height(sid, 1, 1, 34L)),
    section_bar(sid, 4, 1, 6), section_bar(sid, 10, 1, 6), section_bar(sid, 21, 1, 13), section_bar(sid, LW_BAR, 1, 6),
    section_bar(sid, WLD_BAR, 1, 6),
    list(apply_style(sid, 5, 8, 1, 1, STYLE_BODY_BOLD, font_size = 10),
         input_cell(sid, 5, 7, 2, 2, bold = TRUE, halign = "CENTER"),
         fmt_cells(sid, 5, 6, 2, 2, numfmt = NF_DATE), fmt_cells(sid, 7, 7, 2, 2, numfmt = NF_NUM0),
         fmt_cells(sid, 8, 8, 2, 2, halign = "CENTER", font_color = COL_MUTED_TEXT),
         apply_style(sid, 5, 8, 3, 3, STYLE_SUBTITLE, font_size = 9, wrap = FALSE),
         band_hdr(sid, 11, 1, 5, COL_BRAND), band_hdr(sid, 11, 6, 6, C_SLATE), fmt_row_height(sid, 11, 11, 38L),
         # only the priority weights are inputs here: every name is matched literally by formulas and Tasks rows (grey = fixed)
         fixed_cell(sid, 12, 15, 1, 2), fixed_cell(sid, 12, 18, 4, 4), fixed_cell(sid, 12, 16, 5, 5), fixed_cell(sid, 12, 19, 6, 6),
         input_cell(sid, 12, 15, 3, 3),
         fmt_cells(sid, 12, 15, 3, 3, halign = "CENTER"),
         apply_style(sid, 20, 20, 1, 1, STYLE_SUBTITLE, font_size = 9, wrap = FALSE),
         # how risk is scored: label, input weight, note
         apply_style(sid, LW1, LW1 + 3L, 1, 1, STYLE_BODY_BOLD, font_size = 10),
         input_cell(sid, LW1, LW1 + 3L, 2, 2, bold = TRUE, halign = "CENTER"),
         fmt_cells(sid, LW1, LW1 + 3L, 2, 2, numfmt = NF_NUM0),
         apply_style(sid, LW1, LW1 + 3L, 3, 3, STYLE_SUBTITLE, font_size = 9, wrap = FALSE),
         apply_style(sid, LW_DEF, LW_DEF, 1, 1, STYLE_SUBTITLE, font_size = 9, wrap = FALSE),
         # workload limits: label, input, note
         apply_style(sid, WLD1, WLD_LAST, 1, 1, STYLE_BODY_BOLD, font_size = 10),
         input_cell(sid, WLD1, WLD_LAST, 2, 2, bold = TRUE, halign = "CENTER"),
         fmt_cells(sid, WLD1, WLD_LAST, 2, 2, numfmt = NF_NUM0),
         apply_style(sid, WLD1, WLD_LAST, 3, 3, STYLE_SUBTITLE, font_size = 9, wrap = FALSE),
         fmt_borders(sid, 12, 19, 1, 6, inner_h = thin, bottom = thin),
         band_hdr(sid, BD_HDR, 1, 2, C_SLATE), band_hdr(sid, BD_HDR, 4, 8, C_SLATE), band_hdr(sid, BD_HDR, 10, 13, C_SLATE),
         fmt_row_height(sid, BD_HDR, BD_HDR, 36L),
         fmt_cells(sid, BD_ROW1, BD_WK_LAST, 1, 13, halign = "LEFT"),
         fmt_cells(sid, BD_ROW1, BD_ROW1 + 4L, 5, 8, halign = "CENTER"),
         fmt_cells(sid, BD_ROW1, BD_ROW1 + 3L, 2, 2, halign = "CENTER"),
         fmt_cells(sid, BD_ROW1, BD_WK_LAST, 10, 10, numfmt = NF_DSHORT, halign = "CENTER"),
         fmt_cells(sid, BD_ROW1, BD_WK_LAST, 11, 11, halign = "CENTER"),
         fmt_cells(sid, BD_ROW1, BD_ROW1 + 4L, 5, 8, numfmt = list(type = "NUMBER", pattern = "0;-0;;@"), halign = "CENTER"),   # zeros blank: no "0" data labels
         fmt_cells(sid, BD_ROW1, BD_WK_LAST, 12, 13, numfmt = NUMFMT_INT, halign = "CENTER"),
         fmt_borders(sid, BD_ROW1, BD_ROW1 + 3L, 1, 2, inner_h = thin, bottom = thin),
         fmt_borders(sid, BD_ROW1, BD_ROW1 + 4L, 4, 8, inner_h = thin, bottom = thin),
         fmt_borders(sid, BD_ROW1, BD_WK_LAST, 10, 13, inner_h = thin, bottom = thin)))
}

# ---- Tasks -------------------------------------------------------------------
fmt_tasks <- function(sid) {
  b <- new_batch()
  b$push(c(list(fmt_gridlines(sid, FALSE), fmt_freeze(sid, rows = T_HDR, cols = 2L), fmt_tab_color(sid, hex_to_color("163A85"))),
    fmt_col_widths(sid, c(60, 270, 140, 80, 72, 100, 100, 100, 70, 110, 76, 84, 76, 80, 76, 92)),
    list(body_fmt(sid, T_AGG, 16), title_fmt(sid, 1, 1), sub_fmt(sid, 2, 2),
         fmt_row_height(sid, 1, 1, 36L), fmt_row_height(sid, 2, 2, 24L), fmt_row_height(sid, T_HDR, T_HDR, 40L),
         fmt_row_height(sid, T_ROW1, T_AGG, 26L),
         fmt_cells(sid, 2, 2, 1, 1, font_color = C_INPUT, bold = TRUE, halign = "CENTER"),
         band_hdr(sid, T_HDR, 1, 9, COL_BRAND), band_hdr(sid, T_HDR, 10, 10, C_SLATE), band_hdr(sid, T_HDR, 11, 11, COL_BRAND),
         band_hdr(sid, T_HDR, 12, 16, C_SLATE),
         fmt_cells(sid, T_ROW1, T_AGG, 1, 9, font_color = C_INPUT), fmt_cells(sid, T_ROW1, T_AGG, 11, 11, font_color = C_INPUT),
         fmt_cells(sid, T_ROW1, T_AGG, 1, 1, halign = "CENTER"), fmt_cells(sid, T_ROW1, T_AGG, 5, 5, halign = "CENTER"),
         fmt_cells(sid, T_ROW1, T_AGG, 7, 8, numfmt = NF_DATE, halign = "CENTER"), fmt_cells(sid, T_ROW1, T_AGG, 9, 9, numfmt = NUMFMT_PCT_WHOLE, halign = "CENTER"),
         fmt_cells(sid, T_ROW1, T_AGG, 11, 11, numfmt = NUMFMT_INT, halign = "RIGHT"), fmt_cells(sid, T_ROW1, T_AGG, 12, 12, numfmt = NF_DEC1, halign = "RIGHT"),
         fmt_cells(sid, T_ROW1, T_AGG, 13, 13, numfmt = NF_NUM0, halign = "CENTER"),
         fmt_cells(sid, T_ROW1, T_AGG, 14, 16, halign = "CENTER"),
         fmt_cells(sid, T_ROW1, T_AGG, 15, 15, numfmt = NF_NUM0, halign = "CENTER"),
         fmt_borders(sid, T_HDR, T_ROWN, 1, 16, bottom = list(style = "SOLID", color = C_GRID), inner_h = thin),
         fmt_dropdown_range(sid, T_ROW1, T_AGG, 3, 3, paste0("=", L_WS)),
         fmt_dropdown_range(sid, T_ROW1, T_AGG, 4, 4, paste0("=", L_OWNER)),
         fmt_dropdown_range(sid, T_ROW1, T_AGG, 5, 5, paste0("=", L_PRIO)),
         fmt_dropdown_range(sid, T_ROW1, T_AGG, 6, 6, paste0("=", L_STATUS)),
         fmt_validation(sid, T_ROW1, T_AGG, 9, 9, "NUMBER_BETWEEN", c(0, 1), input_message = "Enter 0% to 100%"),
         fmt_validation(sid, T_ROW1, T_AGG, 7, 8, "DATE_IS_VALID", input_message = "Enter a date"),
         fmt_basic_filter(sid, T_HDR, T_ROWN, 1, 16))))
  # Rules: the first one listed wins per cell (b$cf numbers them 0, 1, 2... for this tab).
  # A task with an ID but no owner shows under All people only: flag the empty Owner cell.
  b$cf(fmt_cond_formula, sid, T_ROW1, T_AGG, 4, 4, '=AND($A4<>"",$D4="")', bg_color = hex_to_color("F7B2B2"))
  # These skip column J (the progress-bar sparkline keeps its own fill): one rule per column block, A:I then K:N.
  blocks <- function(formula, ...) for (cc in list(c(1L, 9L), c(11L, 14L)))
    b$cf(fmt_cond_formula, sid, T_ROW1, T_AGG, cc[1L], cc[2L], formula, ...)
  blocks('=$F4="Done"', font_color = C_GREY_FG)
  b$cf(fmt_cond_formula, sid, T_ROW1, T_AGG, 8, 8, '=$N4="Overdue"', bg_color = C_RED_BG, font_color = COL_RED_TEXT, bold = TRUE)
  blocks('=$F4="Blocked"', bg_color = C_AMB_BG)
  blocks('=$N4="Overdue"', bg_color = C_RED_BG)
  b$cf(fmt_cond_color_scale, sid, T_ROW1, T_AGG, 15, 15, COL_WHITE, C_RISK_BG, hex_to_color("F7B2B2"))
  for (q in list(list("Overdue", C_RED_BG, COL_RED_TEXT), list("Blocked", C_AMB_BG, C_AMB_FG),
                 list("At risk", C_RISK_BG, C_RISK_FG), list("On track", C_GRN_BG, C_GRN_FG), list("Done", C_GREY_BG, C_GREY_FG)))
    b$cf(fmt_cond_text_equals, sid, T_ROW1, T_AGG, 16, 16, q[[1]], bg_color = q[[2]], font_color = q[[3]], bold = TRUE)
  # alternating bands drawn only on rows that hold a task (last, so Blocked / Overdue fills win): new rows band themselves
  b$cf(fmt_cond_formula, sid, T_ROW1, T_AGG, 1, 16, '=AND($A4<>"",MOD(ROW(),2)=1)', bg_color = C_BAND)
  b$get()
}

# ---- Timeline ----------------------------------------------------------------
fmt_timeline <- function(sid) {
  b <- new_batch()
  key <- unlist(lapply(seq_along(STATUSES), function(i) {            # colour key chips, same fills as the bars
    c1 <- TL_KEY + 2L * (i - 1L)
    list(fmt_merge(sid, 2, 2, c1, c1 + 1L),
         apply_style(sid, 2, 2, c1, c1 + 1L, STYLE_BODY_BOLD, font_size = 9, halign = "CENTER", valign = "MIDDLE", wrap = FALSE,
                     bg_color = hex_to_color(ST_HEX[[STATUSES[i]]]),
                     font_color = if (STATUSES[i] == "In progress") COL_WHITE else COL_INK),   # white only where it reaches 4.5:1
         fmt_borders(sid, 2, 2, c1, c1 + 1L, left = list(style = "SOLID_THICK", color = COL_WHITE),
                     right = list(style = "SOLID_THICK", color = COL_WHITE)))
  }), recursive = FALSE)
  b$push(c(list(fmt_gridlines(sid, FALSE), fmt_freeze(sid, rows = TL_HDR, cols = 2L), fmt_tab_color(sid, hex_to_color("5B8DEF"))),
    fmt_col_widths(sid, c(52, 220, 72, 84, 70, 70)), fmt_col_widths(sid, rep(50, N_WEEKS), start_col = TL_W1),
    list(body_fmt(sid, TL_ROWN + 5L, TL_WN), title_fmt(sid, 1, 1), sub_fmt(sid, 2, 1),
         fmt_row_height(sid, 1, 1, 36L), fmt_row_height(sid, 2, 2, 24L), fmt_row_height(sid, 3, 3, 22L),
         fmt_row_height(sid, TL_HDR, TL_HDR, 30L),
         fmt_row_height(sid, TL_ROW1, TL_ROWN, 24L),
         fmt_cells(sid, 3, 3, 2, 2, halign = "RIGHT", italic = TRUE, font_color = COL_MUTED_TEXT, font_size = 9),
         fmt_cells(sid, 3, 3, 3, 3, numfmt = NF_DSHORT, halign = "CENTER", bold = TRUE),
         fmt_cells(sid, 3, 3, TL_W1, TL_WN, halign = "CENTER", font_color = hex_to_color("D97706"), font_size = 12),
         fmt_cells(sid, TL_HDR, TL_HDR, TL_W1, TL_WN, numfmt = NF_DSHORT),
         band_hdr(sid, TL_HDR, 1, 6, C_SLATE), band_hdr(sid, TL_HDR, TL_W1, TL_WN, COL_BRAND, size = 9),
         fmt_cells(sid, TL_ROW1, TL_ROWN, 1, 1, halign = "CENTER"),
         fmt_cells(sid, TL_ROW1, TL_ROWN, 5, 6, numfmt = NF_DSHORT, halign = "CENTER"),
         fmt_borders(sid, TL_HDR, TL_ROWD, 1, TL_WN, bottom = thin, inner_h = thin),
         fmt_borders(sid, TL_ROW1, TL_ROWD, TL_W1, TL_WN, inner_v = list(style = "SOLID", color = hex_to_color("EDF0F6")))),
    key))
  # Rules: the first one listed wins per cell (b$cf numbers them 0, 1, 2... for this tab).
  for (s in c("Done", "Blocked", "In progress", "Not started"))       # one bar colour per status
    b$cf(fmt_cond_formula, sid, TL_ROW1, TL_ROWN, TL_W1, TL_WN,
         sprintf('=AND($D5="%s",G$4<=$F5,G$4+6>=$E5)', s), bg_color = hex_to_color(ST_HEX[[s]]))
  # as-of stripe only on rows that hold a task
  b$cf(fmt_cond_formula, sid, TL_ROW1, TL_ROWN, TL_W1, TL_WN, '=AND($A5<>"",$C$3>=G$4,$C$3<=G$4+6)', bg_color = C_ASOF)
  b$cf(fmt_cond_formula, sid, TL_HDR, TL_HDR, TL_W1, TL_WN, '=AND($C$3>=G$4,$C$3<=G$4+6)',
       bg_color = hex_to_color("F5A524"), font_color = COL_INK, bold = TRUE)
  b$cf(fmt_cond_formula, sid, TL_ROW1, TL_ROWN, 6, 6, '=AND($A5<>"",$D5<>"Done",$F5<$C$3)', font_color = COL_RED_TEXT, bold = TRUE)
  b$get()
}

# ---- Workload ----------------------------------------------------------------
fmt_workload <- function(sid) {
  b <- new_batch()
  tot <- function(r, c1, c2) c(list(apply_style(sid, r, r, c1, c2, STYLE_TOTAL, font_size = 10),
                                    fmt_borders(sid, r, r, c1, c2, top = list(style = "SOLID", color = COL_BRAND))))
  b$push(c(list(fmt_gridlines(sid, FALSE), fmt_freeze(sid, rows = 2L), fmt_tab_color(sid, hex_to_color("5B6B8C"))),
    fmt_col_widths(sid, c(16, 110, 96, 96, 96, 96, 80, 80, 96, 104, 100, 170)),
    list(body_fmt(sid, 40L, 13), title_fmt(sid, 1, 2), sub_fmt(sid, 2, 2), fmt_row_height(sid, 1, 1, 36L),
         fmt_row_height(sid, WL_T1_HDR, WL_T1_HDR, 40L), fmt_row_height(sid, WL_T2_HDR, WL_T2_HDR, 40L),
         fmt_row_height(sid, WL_T1_ROW1, WL_T1_TOT, 26L), fmt_row_height(sid, WL_T2_ROW1, WL_T2_TOT, 26L)),
    section_bar(sid, 4, 2, 12), section_bar(sid, WL_T2_HDR - 1L, 2, 6),
    list(band_hdr(sid, WL_T1_HDR, 2, 12, C_SLATE), band_hdr(sid, WL_T1_HDR, 10, 10, COL_BRAND),
         band_hdr(sid, WL_T2_HDR, 2, 6, C_SLATE),
         fmt_cells(sid, WL_T1_ROW1, WL_T1_TOT, 2, 2, bold = TRUE), fmt_cells(sid, WL_T2_ROW1, WL_T2_TOT, 2, 2, bold = TRUE),
         fmt_cells(sid, WL_T1_ROW1, WL_T1_TOT, 3, 10, numfmt = NUMFMT_INT, halign = "CENTER"),
         fmt_cells(sid, WL_T1_ROW1, WL_T1_TOT, 11, 11, numfmt = NF_DEC1, halign = "CENTER"),
         input_cell(sid, WL_T1_ROW1, WL_T1_ROWN, 10, 10, bold = TRUE),
         fmt_cells(sid, WL_T2_ROW1, WL_T2_TOT, 3, 6, numfmt = NUMFMT_INT, halign = "CENTER"),       # whole hours: also the chart's axis format
         fmt_borders(sid, WL_T1_HDR, WL_T1_TOT, 2, 12, inner_h = thin, bottom = thin),
         fmt_borders(sid, WL_T2_HDR, WL_T2_TOT, 2, 6, inner_h = thin, bottom = thin),
         fmt_merge(sid, WL_T2_TOT + 2L, WL_T2_TOT + 2L, 2, 6),
         apply_style(sid, WL_T2_TOT + 2L, WL_T2_TOT + 2L, 2, 6, STYLE_SUBTITLE, font_size = 9, wrap = TRUE, valign = "TOP"),
         fmt_row_height(sid, WL_T2_TOT + 2L, WL_T2_TOT + 2L, 44L)),
    tot(WL_T1_TOT, 2, 12), tot(WL_T2_TOT, 2, 6)))
  # Rules: the first one listed wins per cell (b$cf numbers them 0, 1, 2... for this tab).
  b$cf(fmt_cond_color_scale, sid, WL_T1_ROW1, WL_T1_ROWN, 3, 6, COL_WHITE, hex_to_color("DCE6FA"), hex_to_color("7FA1EA"))
  b$cf(fmt_cond_color_scale, sid, WL_T2_ROW1, WL_T2_ROWN, 3, 5, COL_WHITE, hex_to_color("FDE7B0"), hex_to_color("F2A365"))
  b$cf(fmt_cond_formula, sid, WL_T1_ROW1, WL_T1_TOT, 11, 11, sprintf('=AND(ISNUMBER($K%d),$K%d>INDIRECT("%s"))', WL_T1_ROW1, WL_T1_ROW1, OVERLOAD_REF),
       font_color = COL_RED_TEXT, bold = TRUE)
  b$cf(fmt_cond_number, sid, WL_T1_ROW1, WL_T1_ROWN, 8, 8, 0, font_color = COL_RED_TEXT, bold = TRUE)
  b$get()
}

# ---- Command Center ----------------------------------------------------------
fmt_cc <- function(sid) {
  card_cols <- lapply(kpi_cols, function(c1) c(c1, c1 + 1L))
  accent <- list(COL_BRAND, COL_BRAND, COL_NEGATIVE, COL_WARNING, COL_BRAND, COL_BRAND)
  cards <- unlist(lapply(seq_along(card_cols), function(k) {
    c1 <- card_cols[[k]][1]; c2 <- card_cols[[k]][2]
    list(fmt_merge(sid, 4, 4, c1, c2), fmt_merge(sid, 5, 5, c1, c2), fmt_merge(sid, 6, 6, c1, c2),
         fmt_cells(sid, 4, 6, c1, c2, bg_color = C_CARD, halign = "CENTER"),
         fmt_borders(sid, 4, 6, c1, c2, top = list(style = "SOLID_THICK", color = accent[[k]]),
                     left = list(style = "SOLID_THICK", color = COL_WHITE), right = list(style = "SOLID_THICK", color = COL_WHITE)))
  }), recursive = FALSE)
  att_hdr_merges <- list(c(3, 6), c(7, 8), c(12, 13))
  att_merges <- unlist(lapply(46:51, function(rr) lapply(att_hdr_merges, function(m) fmt_merge(sid, rr, rr, m[1], m[2]))), recursive = FALSE)
  text_merges <- list(fmt_merge(sid, 1, 1, 2, 10), fmt_merge(sid, 1, 1, 11, 13), fmt_merge(sid, 7, 7, 2, 13),
                      fmt_merge(sid, 52, 52, 2, 9), fmt_merge(sid, 52, 52, 10, 13), fmt_merge(sid, 2, 2, 2, 8), fmt_merge(sid, 2, 2, 9, 10), fmt_merge(sid, 2, 2, 11, 13),
                      fmt_merge(sid, 43, 43, 2, 13), fmt_merge(sid, 54, 54, 2, 13), fmt_merge(sid, 55, 55, 2, 13), fmt_merge(sid, 56, 56, 2, 13))
  label_row <- function(r) c(list(fmt_merge(sid, r, r, 2, 13),
    apply_style(sid, r, r, 2, 13, STYLE_BODY_BOLD, font_size = 10, font_color = COL_BRAND_DEEP, halign = "LEFT", valign = "BOTTOM"),
    fmt_borders(sid, r, r, 2, 13, bottom = list(style = "SOLID_MEDIUM", color = COL_BRAND)), fmt_row_height(sid, r, r, 28L)))
  b <- new_batch()
  b$push(c(list(fmt_gridlines(sid, FALSE), fmt_freeze(sid, rows = 2L), fmt_tab_color(sid, COL_BRAND)),
    fmt_col_widths(sid, c(16, rep(CC_COLW, 12), 16)),
    list(body_fmt(sid, 60L, 14), fmt_row_height(sid, 1, 1, 48L), fmt_row_height(sid, 2, 2, 30L), fmt_row_height(sid, 3, 3, 10L),
         fmt_row_height(sid, 4, 4, 26L), fmt_row_height(sid, 5, 5, 52L), fmt_row_height(sid, 6, 6, 26L), fmt_row_height(sid, 7, 7, 28L)),
    text_merges, cards,
    list(apply_style(sid, 1, 1, 2, 10, STYLE_BRAND_TITLE, font_size = 26),
         apply_style(sid, 1, 1, 11, 13, STYLE_SUBTITLE, font_size = 9, halign = "RIGHT", valign = "MIDDLE", wrap = FALSE),   # credit chip (link added last)
         apply_style(sid, 52, 52, 2, 9, STYLE_SUBTITLE, font_size = 9, halign = "LEFT", valign = "MIDDLE", wrap = FALSE),
         apply_style(sid, 52, 52, 10, 13, STYLE_SUBTITLE, font_size = 9, halign = "RIGHT", valign = "MIDDLE", wrap = FALSE),
         apply_style(sid, 2, 2, 2, 8, STYLE_SUBTITLE, font_size = 10, wrap = FALSE),
         apply_style(sid, 2, 2, 9, 10, STYLE_BODY_BOLD, font_size = 10, font_color = COL_MUTED_TEXT, halign = "RIGHT"),
         input_cell(sid, 2, 2, 11, 13, bold = TRUE, font_size = 11, halign = "CENTER"),
         fmt_borders(sid, 2, 2, 11, 13, top = list(style = "SOLID", color = COL_BRAND), bottom = list(style = "SOLID", color = COL_BRAND),
                     left = list(style = "SOLID", color = COL_BRAND), right = list(style = "SOLID", color = COL_BRAND)),
         fmt_dropdown_range(sid, 2, 2, 11, 13, paste0("=", L_PICK)),
         apply_style(sid, 4, 4, 2, 13, STYLE_BODY_BOLD, font_size = 9, font_color = COL_MUTED_TEXT, halign = "CENTER", valign = "BOTTOM"),
         apply_style(sid, 5, 5, 2, 13, STYLE_BODY_BOLD, font_size = 30, font_color = COL_BRAND_DEEP, halign = "CENTER"),
         apply_style(sid, 6, 6, 2, 13, STYLE_SUBTITLE, font_size = 9, halign = "CENTER", valign = "TOP", wrap = FALSE),
         apply_style(sid, 7, 7, 2, 13, STYLE_BODY_BOLD, font_size = 10, font_color = C_SLATE, halign = "CENTER", valign = "MIDDLE", wrap = FALSE),
         fmt_cells(sid, 5, 5, 2, 3, numfmt = NUMFMT_INT), fmt_cells(sid, 5, 5, 4, 5, numfmt = NUMFMT_PCT_WHOLE), fmt_cells(sid, 5, 5, 6, 9, numfmt = NUMFMT_INT),
         fmt_cells(sid, 5, 5, 10, 11, numfmt = NF_HRS), fmt_cells(sid, 5, 5, 12, 13, numfmt = NUMFMT_PCT_WHOLE),
         apply_style(sid, 43, 43, 2, 13, STYLE_SUBTITLE, font_size = 9, wrap = TRUE, valign = "TOP"), fmt_row_height(sid, 43, 43, 32L)),
    label_row(8), label_row(26), label_row(45), label_row(53),
    list(fmt_row_height(sid, 9, 24, 20L), fmt_row_height(sid, 25, 25, 12L), fmt_row_height(sid, 27, 42, 20L), fmt_row_height(sid, 44, 44, 12L),
         fmt_row_height(sid, 52, 52, 22L)),
    att_merges,
    list(band_hdr(sid, 46, 2, 13, C_SLATE), fmt_row_height(sid, 46, 46, 28L), fmt_row_height(sid, 47, 51, 28L),
         fmt_cells(sid, 47, 51, 2, 13, halign = "LEFT"), fmt_cells(sid, 47, 51, 2, 2, halign = "CENTER"),
         fmt_cells(sid, 47, 51, 9, 11, halign = "CENTER"), fmt_cells(sid, 47, 51, 12, 13, halign = "CENTER", bold = TRUE),
         fmt_cells(sid, 47, 51, 10, 10, numfmt = NF_DSHORT, halign = "CENTER"), fmt_cells(sid, 47, 51, 11, 11, numfmt = NF_NUM0, halign = "CENTER"),
         fmt_borders(sid, 46, 51, 2, 13, bottom = thin, inner_h = thin),
         apply_style(sid, 54, 54, 2, 13, STYLE_BODY, font_size = 10, wrap = TRUE, valign = "TOP", font_color = COL_MUTED_TEXT),
         fmt_row_height(sid, 54, 54, 64L), fmt_row_height(sid, 55, 56, 22L))))
  # Rules: the first one listed wins per cell (b$cf numbers them 0, 1, 2... for this tab).
  b$cf(fmt_cond_number, sid, 5, 5, 6, 7, 0, font_color = COL_NEGATIVE)
  b$cf(fmt_cond_number, sid, 5, 5, 8, 9, 0, font_color = C_RISK_FG)
  b$cf(fmt_cond_number, sid, 5, 5, 12, 13, 0.75, "greater_eq", font_color = C_GRN_FG)
  b$cf(fmt_cond_number, sid, 5, 5, 12, 13, 0.5, "less", font_color = COL_NEGATIVE)
  b$cf(fmt_cond_color_scale, sid, 47, 51, 11, 11, COL_WHITE, C_RISK_BG, hex_to_color("F7B2B2"))
  for (q in list(list("Overdue", C_RED_BG, COL_RED_TEXT), list("Blocked", C_AMB_BG, C_AMB_FG),
                 list("At risk", C_RISK_BG, C_RISK_FG), list("On track", C_GRN_BG, C_GRN_FG)))
    b$cf(fmt_cond_text_equals, sid, 47, 51, 12, 13, q[[1]], bg_color = q[[2]], font_color = q[[3]], bold = TRUE)
  b$get()
}

# apply per-tab batches (strict: any API error stops the build with the message)
batch_format(ss, fmt_lists(sid_l), strict = TRUE)
batch_format(ss, fmt_tasks(sid_t), strict = TRUE)
batch_format(ss, fmt_timeline(sid_tl), strict = TRUE)
batch_format(ss, fmt_workload(sid_wl), strict = TRUE)
batch_format(ss, fmt_cc(sid_cc), strict = TRUE)

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: protection, filter views, theme, charts, links (own batches)
# ══════════════════════════════════════════════════════════════════════════════
# ponytail: protection is advisory (warningOnly): enforcing it needs editor emails, which do not belong in a public script
# Whole-sheet protection with an editable hole is the only form the API allows for "protect the formulas, leave the inputs open".
batch_format(ss, list(
  fmt_protected_range(sid_t, T_ROW1, T_AGG, 10, 10, description = "Formula: progress bar"),
  fmt_protected_range(sid_t, T_ROW1, T_AGG, 12, 16, description = "Formulas: hours left, days left, overdue, risk, health"),
  fmt_protected_range(sid_tl, 3, TL_ROWN, 1, TL_WN, description = "Timeline is drawn by formulas from the Tasks tab"),
  fmt_protected_range(sid_wl, description = "Formulas. Only the blue capacity inputs are meant to be edited",
                      unprotected_ranges = grid_range(sid_wl, WL_T1_ROW1, WL_T1_ROWN, 10, 10)),
  fmt_protected_range(sid_cc, description = "Dashboard formulas. Use the Owner view picker to filter",
                      unprotected_ranges = grid_range(sid_cc, 2, 2, 11, 13)),
  fmt_protected_range(sid_l, BD_HDR, BD_WK_LAST, 1, 13, description = "Chart data (formulas)"),
  fmt_protected_range(sid_l, 8, 8, 2, 2, description = "Formula"),
  fmt_protected_range(sid_l, 13, 19, 6, 6, description = "Formulas")), strict = TRUE)

# Owner slicer chip on the Tasks tab. A slicer only filters rows (and charts built on its own data range), so it would not
# move the Command Center KPIs and charts, which are formulas: the Owner view picker drives those instead.
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

# Pie slices take their colors from the spreadsheet theme: the first four accents are the status colors.
batch_format(ss, list(fmt_theme_colors(accent1 = ST_HEX[["Not started"]], accent2 = ST_HEX[["In progress"]],
  accent3 = ST_HEX[["Blocked"]], accent4 = ST_HEX[["Done"]], accent5 = "163A85", accent6 = "5B6B8C",
  text = "12161C", background = "FFFFFF", link = "2457C5")), strict = TRUE)

stat_col <- function(s) hex_to_color(ST_HEX[[s]])
# Charts read their data from Lists and sit on another tab (anchor_sheet_id). They fill B..M exactly (CC_W px) so their edges line
# up with the KPI cards and section rules; offset_y = 8 keeps them off the rule above.
CH_STYLE <- list(font = "Arial", title_size = 12, title_bold = TRUE, title_color = COL_INK)   # Arial throughout, bold ink title
pie <- fmt_chart_pie(sid_l, "Tasks by status", donut = TRUE, pie_hole = 0.55,
  domain_range = c(BD_ROW1, BD_ROW1 + 3L, 1, 1), data_range = c(BD_ROW1, BD_ROW1 + 3L, 2, 2),
  anchor = c(9L, 2L), size = c(CC_HALF, 312L), anchor_sheet_id = sid_cc, offset_y = 8L, style = CH_STYLE)
bar <- fmt_chart_bar(sid_l, "Tasks by workstream and status",
  domain_range = c(BD_HDR, BD_ROW1 + 4L, 4, 4),
  series_list = lapply(5:8, function(cc) list(range = c(BD_HDR, BD_ROW1 + 4L, cc, cc), color = stat_col(STATUSES[cc - 4L]),
    # white label only on the blue (6.5:1); green and amber need dark text
    label = list(type = "DATA", placement = "CENTER", textFormat = list(fontFamily = "Arial", fontSize = 10, bold = TRUE,
      foregroundColorStyle = list(rgbColor = if (STATUSES[cc - 4L] == "In progress") COL_WHITE else COL_INK))))),
  header_count = 1L, stacked_type = "STACKED", anchor = c(9L, 8L), size = c(CC_HALF, 312L), legend = "BOTTOM_LEGEND",
  anchor_sheet_id = sid_cc, x_title = "Tasks", offset_x = CC_BAR_DX, offset_y = 8L, style = CH_STYLE)
burn <- fmt_chart_basic(sid_l, "Hours remaining: planned vs actual", "LINE",
  domain_range = c(BD_HDR, BD_WK_LAST, 11, 11),
  series_list = list(list(range = c(BD_HDR, BD_WK_LAST, 12, 12), color = hex_to_color("8A94A6"), line = list(type = "MEDIUM_DASHED")),
                     list(range = c(BD_HDR, BD_WK_LAST, 13, 13), color = COL_BRAND, point = list(size = 7, shape = "CIRCLE"))),
  header_count = 1L, anchor = c(27L, 2L), size = c(CC_W, 312L), legend = "TOP_LEGEND",
  anchor_sheet_id = sid_cc, x_title = "Week starting", y_title = "Hours remaining", offset_y = 8L, style = CH_STYLE)
batch_format(ss, list(pie, bar, burn), strict = TRUE)
batch_format(ss, list(fmt_chart_basic(sid_wl, "Hours remaining by owner and status", "COLUMN",
  domain_range = c(WL_T2_HDR, WL_T2_ROWN, 2, 2),
  series_list = lapply(3:5, function(cc) list(range = c(WL_T2_HDR, WL_T2_ROWN, cc, cc), color = stat_col(STATUSES[cc - 2L]))),
  header_count = 1L, stacked_type = "STACKED", anchor = c(WL_T2_HDR - 1L, 8L), size = c(550L, 300L), legend = "BOTTOM_LEGEND",   # H..L = 550 px: flush with the table above
  y_title = "Hours", style = CH_STYLE)), strict = TRUE)

# Rich-text links and the note go in their own last batch
tasks_url <- sprintf("https://docs.google.com/spreadsheets/d/%s/edit#gid=%d", ss_id, sid_t)
# Only Tasks!O3 gets a note: Sheets' PDF export prints every note as a [n] marker plus an extra page, and on the Command Center
# the risk definition is visible text (row 52) instead.
batch_format(ss, list(
  link_cells_req(sid_cc, 1, 11, "Built with r-googlesheets4", REPO_URL),
  link_cells_req(sid_cc, 52, 10, "Open the full task list", tasks_url),
  link_cells_req(sid_cc, 55, 2, c("Built with the r-googlesheets4 skill (github.com/salvadoraveldano/r-googlesheets4)",
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
scan_ranges <- c(sprintf("'%s'!A1:N%d", TAB_CC, CC_LAST_ROW), sprintf("'%s'!A1:P%d", TAB_TASKS, T_AGG),
                 sprintf("'%s'!A1:V%d", TAB_TL, TL_ROWN), sprintf("'%s'!A1:L%d", TAB_WL, 30L), sprintf("'%s'!A1:M%d", TAB_LISTS, WLD_LAST + 4L))
fv_all <- read_values(ss, scan_ranges)
for (i in seq_along(fv_all)) {
  hits <- sum(grepl(err_re, fv_all[[i]]))
  if (hits) bad("%d error value(s) in %s", hits, scan_ranges[i])
}

# 2. formulas agree with the R reference (all people, then one owner)
check_view <- function(owner) {
  e <- expected(tk, owner); b <- burn_expected(tk, owner)
  v <- read_values(ss, c(sprintf("'%s'!B5:M5", TAB_CC), sprintf("'%s'!J%d:M%d", TAB_LISTS, BD_ROW1, BD_WK_LAST)),
                   "UNFORMATTED_VALUE")
  k <- suppressWarnings(as.numeric(v[[1]])); bl <- v[[2]]      # KPI cards are merged pairs: B, D, F, H, J, L hold the values
  got <- c(total = k[1], done = k[3], over = k[5], blocked = k[7], hours = k[9], ontrack = k[11])
  want <- c(total = e$total, done = e$done / e$total, over = e$over, blocked = e$blocked, hours = e$hours, ontrack = e$ontrack)
  lab <- owner %||% ALL_LABEL
  for (nm in names(want)) if (!isTRUE(all.equal(as.numeric(got[[nm]]), as.numeric(want[[nm]]), tolerance = 1e-6)))
    bad("[%s] KPI %s: sheet %s vs expected %s", lab, nm, got[[nm]], want[[nm]])
  planned <- as.numeric(bl[, 3]); actual <- suppressWarnings(as.numeric(bl[, 4]))   # actual is blank after the as-of week
  if (!isTRUE(all.equal(planned, b$planned, tolerance = 1e-6))) bad("[%s] planned burn differs", lab)
  if (!isTRUE(all.equal(actual[!is.na(actual)], b$actual, tolerance = 1e-6))) bad("[%s] actual burn differs", lab)
  if (sum(!is.na(actual)) != length(b$actual)) bad("[%s] actual has %d points, expected %d", lab, sum(!is.na(actual)), length(b$actual))
}
set_picker <- function(who) {
  write_cell(ss, TAB_CC, 2, 11, who); flush_writes(ss, strict = TRUE); Sys.sleep(3)
}
set_picker(ALL_LABEL); check_view(NULL)
set_picker(OWNERS[2]); check_view(OWNERS[2])
set_picker("")                                          # a cleared picker must behave exactly like All people
check_view(NULL)
cap <- read_values(ss, sprintf("'%s'!B6", TAB_CC))[[1]][1, 1]
if (!grepl("^across", cap)) bad("blank picker: card caption reads '%s', expected the All people caption", cap)
set_picker(ALL_LABEL)

# the guarded rows below the sample tasks must stay empty, and the headline cells must read well
spare <- as.vector(read_values(ss, sprintf("'%s'!J%d:P%d", TAB_TASKS, T_ROWN + 1L, T_AGG))[[1]])
if (any(nzchar(spare))) bad("%d non-empty cell(s) in the guarded Tasks rows %d-%d", sum(nzchar(spare)), T_ROWN + 1L, T_AGG)
for (a1 in c("B7", "B8", "B26")) message(sprintf("[headline] %s = %s", a1,
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
