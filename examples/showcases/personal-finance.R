# =============================================================================
# personal-finance.R  -  Showcase: "Personal Finance Tracker - Sample Data"
# =============================================================================
# Builds     One Google Sheet with six tabs: Dashboard (month picker, KPI cards,
#            budget-health strip, 4 charts, top-5 list), Budget (inputs, SUMIFS
#            actuals, variance with red/green rules, live self-checks), Transactions
#            (~370 rows, dropdowns, filter), Net Worth (balances, totals, MoM, 2 charts),
#            Trends (12-month summary, savings chart, native pivot heatmap), Lists.
# Reads      Nothing external. Every row is synthetic and generated below with
#            set.seed(): no real people, merchants, accounts or amounts.
# Access     Default "sheets" level (spreadsheets scope only). No Drive access,
#            no sharing, no installs. Needs the saved login from gs_setup.sh.
# First run  GS_SKILL_DIR=<path to skills/r-googlesheets4> Rscript examples/showcases/personal-finance.R
#            (creates your own copy and prints its id)
# Rerun      SHEET_ID=<id> GS_SKILL_DIR=<path to skills/r-googlesheets4> Rscript examples/showcases/personal-finance.R
#            (rebuilds your sample sheet in place: the six tabs below are cleared and rebuilt, nothing piles up.
#             Safety: gs_open_or_create() stops before changing anything when the file's title is not
#             SHEET_TITLE below and the file lacks these tabs, or when its locale is not the one below,
#             so a wrong id is refused.)
#
# Built with the r-googlesheets4 skill (https://github.com/salvadoraveldano/r-googlesheets4),
# on googlesheets4 by Jennifer Bryan and Posit (https://googlesheets4.tidyverse.org).
# =============================================================================

# -- Parameters ---------------------------------------------------------------
SHEET_TITLE <- "Personal Finance Tracker - Sample Data"
USER_EMAIL  <- NULL                      # NULL = the account saved by gs_setup.sh
SEED        <- 2026                      # same seed = same sample data
START_MONTH <- as.Date("2025-10-01")     # first of 12 sample months
N_MONTHS    <- 12L
SELECTED    <- 12L                       # month the Dashboard opens on (1 = first)
LAST_ROW    <- 1000L                     # Transactions rows covered by names, lists, pivot
BUDGET <- c(Housing = 2200, Groceries = 500, Dining = 180, Transport = 210, Utilities = 230,
            Health = 90, Leisure = 70, Shopping = 150, Travel = 150)   # monthly, per category
EXPECTED_INCOME <- 5000                  # monthly income you plan for
SAVINGS_GOAL    <- 0.20                  # savings-rate goal
WARN_AT         <- 0.85                  # share of a budget used where a category turns amber
NO_BUD          <- "no budget"           # what "Used" reads when a category has spending but a zero or blank budget

SKILL <- Sys.getenv("GS_SKILL_DIR", ".")   # the skill directory (default: run from it)
if (!file.exists(file.path(SKILL, "scripts", "gs_helpers.R")))
  stop("Set GS_SKILL_DIR to the skill directory (skills/r-googlesheets4 in the repo); no scripts/gs_helpers.R in '", SKILL, "'.", call. = FALSE)
for (f in c("gs_helpers.R", "gs_buffer.R", "gs_qa.R", "gs_formulas.R",
            "gs_charts.R", "gs_modern.R", "brand.R"))
  source(file.path(SKILL, "scripts", f))

gs_connect(USER_EMAIL)   # saved login only; never opens a browser

# -- Names, palette, styles ---------------------------------------------------
T_DASH <- "Dashboard"; T_BUD <- "Budget"; T_TXN <- "Transactions"
T_NW <- "Net Worth"; T_TRD <- "Trends"; T_LST <- "Lists"
TABS <- c(T_DASH, T_BUD, T_TXN, T_NW, T_TRD, T_LST)

PAL <- c(blue = "2457C5", teal = "12A59A", amber = "F5A524", violet = "7C5CFC",
         sky = "5AA9F0", slate = "8A94A6", navy = "163A85")     # chart / card accents
COL_PANEL    <- hex_to_color("F4F6FB")     # card + chart background
COL_INPUT_BG <- hex_to_color("FFF6D6")     # pale yellow: input cells
COL_INPUT_FG <- hex_to_color("1A4FD6")     # blue text: typed-in values
COL_SLATE    <- hex_to_color("5F6B7A")     # muted text
COL_HAIR     <- hex_to_color("D5DBE6")     # hairlines
WHITE_THICK  <- list(style = "SOLID_THICK", color = COL_WHITE)

num <- function(p) list(type = "NUMBER", pattern = p)
NF_USD     <- NUMFMT_CURRENCY               # $#,##0;($#,##0);"-"
NF_USD_NEG <- num('$#,##0;-$#,##0')         # also used on chart sources: zero reads $0, not "-"
NF_USD2    <- num('$#,##0.00')
NF_USD2C   <- num('$#,##0.00;($#,##0.00);"-"')   # cents, so a column adds up to the cent
NF_PCT1    <- NUMFMT_PCT                    # 0.0%
NF_PCT0    <- NUMFMT_PCT_WHOLE              # 0%
NF_PTS     <- num('+0.0" pts";-0.0" pts";0.0" pts"')   # percentage points (value is already x100)
NF_INT     <- num("0")
NF_MONTH_LONG <- list(type = "DATE", pattern = "mmmm yyyy")
NF_MONTH      <- list(type = "DATE", pattern = "mmm yyyy")
NF_DAY        <- list(type = "DATE", pattern = "mmm d, yyyy")

GOOD <- list(fg = hex_to_color("0F6B3A"), bg = hex_to_color("D9F2E3"))
WARN <- list(fg = hex_to_color("8A5A00"), bg = hex_to_color("FEEFC8"))
BAD  <- list(fg = hex_to_color("9B1C1C"), bg = hex_to_color("FBD5D5"))

# One look for all seven charts. The border matches the panel: Google's default dark outline would show a sliver of it.
CHART_STYLE <- list(font = "Arial", title_size = 12, title_bold = TRUE, title_color = COL_INK, title_position = "LEFT",
                    background = COL_PANEL, border = COL_PANEL, axis_font_size = 9)

# -- Synthetic data -----------------------------------------------------------
set.seed(SEED)
months  <- seq(START_MONTH, by = "month", length.out = N_MONTHS)
days_in <- function(d) as.integer(format(seq(d, by = "month", length.out = 2)[2] - 1, "%d"))
CAT_EXP <- names(BUDGET)
CAT_INC <- c("Salary", "Side income", "Interest")
ACCOUNTS <- c("Checking", "Credit Card", "Savings")

rows <- list()
add <- function(date, merchant, category, account, amount, type) {
  n <- length(date); if (n == 0L) return(invisible())
  rows[[length(rows) + 1L]] <<- data.frame(
    Date = date, Merchant = merchant, Category = category, Account = rep_len(account, n),
    Amount = round(rep_len(amount, n), 2), Type = type, stringsAsFactors = FALSE)
}
pick_days <- function(d0, n) if (n < 1L) d0[0] else d0 + sort(sample.int(days_in(d0), n, replace = TRUE)) - 1L
acct <- function(n, p_card = .7) sample(c("Credit Card", "Checking"), n, TRUE, c(p_card, 1 - p_card))

for (i in seq_along(months)) {
  d0 <- months[i]; nd <- days_in(d0); mon <- as.integer(format(d0, "%m"))
  add(d0 + c(14L, nd - 3L), "Payroll Deposit", "Salary", "Checking", if (i <= 6) 2450 else 2520, "Income")
  if (mon %in% c(11, 2, 3, 6, 8))
    add(d0 + sample(5:22, 1), "Client Invoice Payment", "Side income", "Checking", round(runif(1, 320, 940)), "Income")
  add(d0 + nd - 1L, "Savings Interest", "Interest", "Savings", runif(1, 24, 36) + i * 0.4, "Income")
  add(d0, "Rent Payment", "Housing", "Checking", 2150, "Expense")
  add(d0 + 4L, "Renters Insurance", "Housing", "Checking", 24.5, "Expense")
  season <- cos((mon - 1) / 12 * 4 * pi)                      # electric bill peaks in Jan and Jul
  add(d0 + 7L, "Electric Utility", "Utilities", "Checking", 72 + 30 * season + rnorm(1, 0, 6), "Expense")
  add(d0 + 11L, "Water & Sewer", "Utilities", "Checking", 46 + rnorm(1, 0, 3), "Expense")
  add(d0 + 9L, "Internet & Mobile", "Utilities", "Checking", 109.99, "Expense")
  n <- sample(4:5, 1); add(pick_days(d0, n), "Grocery Store", "Groceries", acct(n), pmin(190, pmax(55, rlnorm(n, log(112), .3))), "Expense")
  if (runif(1) < .4) add(pick_days(d0, 1), "Farmers Market", "Groceries", "Credit Card", runif(1, 18, 36), "Expense")
  n <- sample(3:5, 1); add(pick_days(d0, n), "Coffee Shop", "Dining", acct(n, .85), runif(n, 3.9, 7.2), "Expense")
  n <- sample(1:3, 1); add(pick_days(d0, n), "Restaurant", "Dining", acct(n, .85), runif(n, 28, 82), "Expense")
  n <- sample(1:2, 1); add(pick_days(d0, n), "Takeout", "Dining", acct(n, .85), runif(n, 15, 38), "Expense")
  add(d0 + 14L, "Auto Insurance", "Transport", "Checking", 94, "Expense")
  n <- sample(2:3, 1); add(pick_days(d0, n), "Gas Station", "Transport", acct(n, .8), runif(n, 36, 58), "Expense")
  if (runif(1) < .5) add(pick_days(d0, 1), "Rideshare", "Transport", "Credit Card", runif(1, 12, 29), "Expense")
  add(d0 + 2L, "Gym Membership", "Health", "Credit Card", 34.99, "Expense")
  if (runif(1) < .5) add(pick_days(d0, 1), "Pharmacy", "Health", acct(1), runif(1, 9, 41), "Expense")
  if (mon %in% c(1, 5, 9)) add(pick_days(d0, 1), "Doctor Visit", "Health", "Checking", runif(1, 55, 140), "Expense")
  add(d0 + 5L, "Streaming Service", "Leisure", "Credit Card", 15.99, "Expense")
  if (runif(1) < .5) add(pick_days(d0, 1), "Cinema", "Leisure", "Credit Card", runif(1, 13, 31), "Expense")
  if (runif(1) < .45) add(pick_days(d0, 1), "Bookstore", "Leisure", "Credit Card", runif(1, 14, 46), "Expense")
  if (mon %in% c(2, 8)) add(pick_days(d0, 1), "Concert Tickets", "Leisure", "Credit Card", runif(1, 78, 140), "Expense")
  n <- sample(0:2, 1); add(pick_days(d0, n), "Clothing Store", "Shopping", acct(n), runif(n, 32, 115), "Expense")
  if (runif(1) < .4) add(pick_days(d0, 1), "Home Goods Store", "Shopping", acct(1), runif(1, 16, 92), "Expense")
  if (runif(1) < .2) add(pick_days(d0, 1), "Electronics Store", "Shopping", "Credit Card", runif(1, 65, 260), "Expense")
  if (mon %in% c(11, 12)) { n <- sample(3:5, 1); add(pick_days(d0, n), "Gift Shop", "Shopping", "Credit Card", runif(n, 24, 85), "Expense") }
  if (mon == 12) {
    add(d0 + c(2L, 3L), "Airline", "Travel", "Credit Card", c(268.4, 241.9), "Expense")
    add(d0 + 18L, "Hotel", "Travel", "Credit Card", 462, "Expense")
    add(d0 + 19L, "Rental Car", "Travel", "Credit Card", 148.5, "Expense")
  }
  if (mon == 3) { add(d0 + 11L, "Hotel", "Travel", "Credit Card", 195, "Expense"); add(d0 + 10L, "Train Tickets", "Travel", "Credit Card", 88, "Expense") }
  if (mon == 6) { add(d0 + 6L, "Airline", "Travel", "Credit Card", 245, "Expense"); add(d0 + 21L, "Hotel", "Travel", "Credit Card", 330, "Expense") }
}
txn <- do.call(rbind, rows)
txn <- txn[order(txn$Date), ]; rownames(txn) <- NULL
stopifnot(nrow(txn) >= 300, nrow(txn) <= 400, all(txn$Category %in% c(CAT_EXP, CAT_INC)))

# Month-end balances that roughly follow the sample cash flow (still synthetic).
set.seed(SEED + 1)
mkey  <- format(txn$Date, "%Y-%m"); mk <- format(months, "%Y-%m")
inc_m <- sapply(mk, function(k) sum(txn$Amount[mkey == k & txn$Type == "Income"]))
exp_m <- sapply(mk, function(k) sum(txn$Amount[mkey == k & txn$Type == "Expense"]))
card_m <- sapply(mk, function(k) sum(txn$Amount[mkey == k & txn$Account == "Credit Card" & txn$Type == "Expense"]))
net_m <- inc_m - exp_m
nw <- data.frame(Checking = round(4400 + 0.3 * (net_m - mean(net_m)) + rnorm(N_MONTHS, 0, 120)))
sv <- iv <- rt <- numeric(N_MONTHS)
for (i in seq_len(N_MONTHS)) {
  sv[i] <- (if (i == 1) 9800 else sv[i - 1]) * 1.003 + 0.35 * max(net_m[i], 0)
  iv[i] <- (if (i == 1) 18500 else iv[i - 1]) * (1 + rnorm(1, .007, .025)) + 0.30 * max(net_m[i], 0)
  rt[i] <- (if (i == 1) 41200 else rt[i - 1]) * (1 + rnorm(1, .007, .025)) + 650
}
nw$Savings <- round(sv); nw$Investments <- round(iv); nw$Retirement <- round(rt)
nw$CreditCard <- round(card_m * runif(N_MONTHS, .45, .65))
nw$CarLoan <- round(14200 - 365 * (seq_len(N_MONTHS) - 1))
nw$StudentLoan <- round(17600 - 240 * (seq_len(N_MONTHS) - 1))

# -- Workbook: create or reuse, then start from clean tabs ---------------------
# On a rerun gs_open_or_create() refuses a wrong SHEET_ID before it changes anything; gs_reset_tabs() then
# clears only the tabs named. The sample holds dates only (no clock times), so a neutral time zone changes no
# value and does not travel with every copy. time_zone applies on create (a reused file keeps its own); locale
# applies on create too, and a reused file with another locale is refused.
ss <- gs_open_or_create(SHEET_TITLE, TABS, time_zone = "Etc/GMT", locale = "en_US")
gs_reset_tabs(ss, tabs = TABS)   # charts, banding, protection, filters, pivots, names, rules: nothing piles up; sheetIds stay
sid <- sapply(TABS, function(t) get_sheet_id(ss, t))
S_DASH <- sid[[T_DASH]]; S_BUD <- sid[[T_BUD]]; S_TXN <- sid[[T_TXN]]
S_NW <- sid[[T_NW]]; S_TRD <- sid[[T_TRD]]; S_LST <- sid[[T_LST]]

# Theme first (its accents colour the doughnut slices), then the named ranges, so formulas written below resolve on the first pass.
txn_name <- function(nm, col) fmt_named_range(S_TXN, nm, 5L, LAST_ROW, col, col)
batch_format(ss, list(
  fmt_theme_colors(accent1 = PAL[["blue"]], accent2 = PAL[["teal"]], accent3 = PAL[["amber"]], accent4 = PAL[["violet"]],
                   accent5 = PAL[["sky"]], accent6 = PAL[["slate"]], text = "12161C", link = PAL[["blue"]]),
  fmt_named_range(S_LST, "month_start", 5L, 5L, 12L, 12L),
  fmt_named_range(S_LST, "prev_start",  6L, 6L, 12L, 12L),
  fmt_named_range(S_LST, "month_label", 7L, 7L, 12L, 12L),
  fmt_named_range(S_BUD, "warn_at", 21L, 21L, 3L, 3L),            # the one amber threshold (Budget!C21)
  txn_name("txn_date", 2L), txn_name("txn_cat", 4L), txn_name("txn_amt", 6L),
  txn_name("txn_type", 7L), txn_name("txn_month", 8L)), strict = TRUE)

# =============================================================================
# Cell writes (buffered, one API call) + the Transactions table
# =============================================================================
mrow <- function(i) 4L + i     # month i (1..12) sits on row 4+i in Lists, 5+i elsewhere

# -- Lists --
write_cell(ss, T_LST, 2, 2, "Lists")
write_cell(ss, T_LST, 3, 2, "These lists feed every dropdown. Type the first month once and the other eleven follow. Add or rename a category only together with its Transactions rows.")
for (h in list(c(4, 2, "Month"), c(4, 4, "Category"), c(4, 5, "Kind"), c(4, 7, "Account"), c(4, 9, "Type"), c(4, 11, "Derived values")))
  write_cell(ss, T_LST, as.integer(h[1]), as.integer(h[2]), h[3])
write_cell(ss, T_LST, mrow(1), 2, as.character(months[1]))                      # the one input: first month
for (i in seq_len(N_MONTHS)[-1]) write_cell(ss, T_LST, mrow(i), 2, sprintf("=EDATE(B%d,1)", mrow(i - 1L)))
cats <- c(CAT_EXP, CAT_INC); kinds <- c(rep("Expense", length(CAT_EXP)), rep("Income", length(CAT_INC)))
for (i in seq_along(cats)) { write_cell(ss, T_LST, 4L + i, 4, cats[i]); write_cell(ss, T_LST, 4L + i, 5, kinds[i]) }
for (i in seq_along(ACCOUNTS)) write_cell(ss, T_LST, 4L + i, 7, ACCOUNTS[i])
write_cell(ss, T_LST, 5, 9, "Income"); write_cell(ss, T_LST, 6, 9, "Expense")
write_cell(ss, T_LST, 5, 11, "month_start"); write_cell(ss, T_LST, 6, 11, "prev_start"); write_cell(ss, T_LST, 7, 11, "month_label")
write_cell(ss, T_LST, 5, 12, '=IFERROR(IF(COUNTIF($B$5:$B$16,DATE(YEAR(Dashboard!$Q$2),MONTH(Dashboard!$Q$2),1))=0,MAX($B$5:$B$16),DATE(YEAR(Dashboard!$Q$2),MONTH(Dashboard!$Q$2),1)),MAX($B$5:$B$16))')
write_cell(ss, T_LST, 6, 12, "=EDATE(L5,-1)")
write_cell(ss, T_LST, 7, 12, '=TEXT(L5,"mmmm yyyy")')
write_cell(ss, T_LST, 9, 11, "These three follow the month picker on the Dashboard and drive every formula.")

# -- Transactions --
write_cell(ss, T_TXN, 2, 2, "Transactions")
write_cell(ss, T_TXN, 3, 2, sprintf('="Blue cells are inputs. Add rows at the bottom, up to row %d. Dates from "&TEXT(Lists!$B$5,"mmm yyyy")&" to "&TEXT(Lists!$B$16,"mmm yyyy")&" flow to every tab (change the first month on Lists); Type must match the Category (red if not)."', LAST_ROW))
write_cell(ss, T_TXN, 4, 8, "Month")
write_cell(ss, T_TXN, 5, 8, sprintf('=ARRAYFORMULA(IF(B5:B%d="","",DATE(YEAR(B5:B%d),MONTH(B5:B%d),1)))', LAST_ROW, LAST_ROW, LAST_ROW))
write_block(ss, T_TXN, 4, 2, rbind(names(txn)))      # header row
write_block(ss, T_TXN, 5, 2, txn)                      # ~370 rows as ONE buffered range

# -- Budget (rows 6-14 categories, 15 total, 18-20 income and savings, 25-30 chart data) --
write_cell(ss, T_BUD, 2, 2, "Budget vs actual")
write_cell(ss, T_BUD, 3, 2, '="Showing "&month_label&". Change the month on the Dashboard. Blue cells on yellow are inputs. Variance = budget minus actual: positive (green) is under budget."')
hdr_b <- c("Category", "Monthly budget", "Actual", "Variance", "Variance %", "Used", "Progress", "Status")
for (j in seq_along(hdr_b)) write_cell(ss, T_BUD, 5, 1L + j, hdr_b[j])
for (k in seq_along(CAT_EXP)) {
  r <- 5L + k
  write_cell(ss, T_BUD, r, 2, sprintf("=Lists!$D%d", 4L + k))
  write_cell(ss, T_BUD, r, 3, BUDGET[[k]])
  write_cell(ss, T_BUD, r, 4, sprintf('=SUMIFS(txn_amt,txn_cat,$B%d,txn_type,"Expense",txn_month,month_start)', r))
}
write_cell(ss, T_BUD, 15, 2, "Total spending")
write_cell(ss, T_BUD, 15, 3, "=SUM(C6:C14)"); write_cell(ss, T_BUD, 15, 4, "=SUM(D6:D14)")
for (r in c(6:15, 18:19)) {                       # variance, %, used, bar, status share one pattern
  write_cell(ss, T_BUD, r, 5, if (r == 18) "=D18-C18" else if (r == 19) "=D19-C19" else sprintf("=C%d-D%d", r, r))
  # Planned savings = income minus the budget and can be tiny or negative: no % against a base <= 0
  write_cell(ss, T_BUD, r, 6, if (r == 19) '=IF(C19<=0,"",E19/C19)' else f_safe_div(sprintf("E%d", r), sprintf("C%d", r)))
}
for (r in 6:15) {
  # Used: spending / budget. A zero or blank budget with spending reads "no budget" (counts as over budget below);
  # no budget and no spending stays blank.
  write_cell(ss, T_BUD, r, 7, sprintf('=IF(C%d<=0,IF(D%d>0,"%s",""),D%d/C%d)', r, r, NO_BUD, r, r))
  # 1.2 is only the bar's display cap (120% of the track); 1 (= 100%) is what "over budget" means; "no budget" draws a full red bar
  bar <- f_sparkline(sprintf("MIN(IF(ISNUMBER(G%d),G%d,1.2),1.2)", r, r), list(charttype = "bar", max = 1.2,
           color1 = I(sprintf('IF(NOT(ISNUMBER(G%d)),"#E5484D",IF(G%d>1,"#E5484D",IF(G%d>=warn_at,"#F5A524","#18A957")))', r, r, r))))
  write_cell(ss, T_BUD, r, 8, sprintf('=IF(G%d="","",%s)', r, fraw(bar)))
  write_cell(ss, T_BUD, r, 9, sprintf('=IF(G%d="","",IF(ISNUMBER(G%d),IF(G%d>1,"Over budget",IF(G%d>=warn_at,"Close to limit","On track")),"No budget"))', r, r, r, r))
}
for (j in 1:5) write_cell(ss, T_BUD, 17, 1L + j, c("Income and savings", "Planned", "Actual", "Difference", "Difference %")[j])
write_cell(ss, T_BUD, 18, 2, "Income"); write_cell(ss, T_BUD, 18, 3, EXPECTED_INCOME)
write_cell(ss, T_BUD, 18, 4, '=SUMIFS(txn_amt,txn_type,"Income",txn_month,month_start)')
write_cell(ss, T_BUD, 19, 2, "Savings"); write_cell(ss, T_BUD, 19, 3, "=C18-C15"); write_cell(ss, T_BUD, 19, 4, "=D18-D15")
write_cell(ss, T_BUD, 20, 2, "Savings-rate goal"); write_cell(ss, T_BUD, 20, 3, SAVINGS_GOAL)
write_cell(ss, T_BUD, 20, 4, "=IFERROR(D19/D18,0)"); write_cell(ss, T_BUD, 20, 5, "=(D20-C20)*100")   # percentage points
write_cell(ss, T_BUD, 21, 2, "Warning threshold"); write_cell(ss, T_BUD, 21, 3, WARN_AT)
write_cell(ss, T_BUD, 21, 4, "A category turns amber at this share of its budget (red above 100%). Drives the status, the bars and the Dashboard strip.")
write_cell(ss, T_BUD, 23, 2, "Chart data: top spending categories for the selected month (feeds the Dashboard doughnut and Top 5 list)")
write_cell(ss, T_BUD, 24, 2, "Category"); write_cell(ss, T_BUD, 24, 3, "Spent")
for (k in 1:5) {
  write_cell(ss, T_BUD, 24L + k, 2, sprintf("=INDEX(SORT({$B$6:$B$14,$D$6:$D$14},2,FALSE),%d,1)", k))
  write_cell(ss, T_BUD, 24L + k, 3, sprintf("=INDEX(SORT({$B$6:$B$14,$D$6:$D$14},2,FALSE),%d,2)", k))
}
# whole dollars that add up: the rounded total minus the rounded top 5 (the Dashboard top-5 list shows this same cell)
write_cell(ss, T_BUD, 30, 2, "Everything else"); write_cell(ss, T_BUD, 30, 3, "=ROUND(D15,0)-SUMPRODUCT(ROUND(C25:C29,0))")
# chart data 2: share of budget used, biggest first (feeds the Dashboard budget chart); blanks count as 0, "no budget" as 200% (the axis top)
write_cell(ss, T_BUD, 32, 2, "Chart data: share of each budget used, sorted (feeds the Dashboard budget chart)")
write_cell(ss, T_BUD, 33, 2, "Category"); write_cell(ss, T_BUD, 33, 3, "% of budget used"); write_cell(ss, T_BUD, 33, 4, "100% limit")
for (k in 1:9) {
  srt <- '{$B$6:$B$14,ARRAYFORMULA(IF(ISNUMBER($G$6:$G$14),$G$6:$G$14,IF($G$6:$G$14="",0,2)))}'
  write_cell(ss, T_BUD, 33L + k, 2, sprintf("=INDEX(SORT(%s,2,FALSE),%d,1)", srt, k))
  write_cell(ss, T_BUD, 33L + k, 3, sprintf("=INDEX(SORT(%s,2,FALSE),%d,2)", srt, k))
  write_cell(ss, T_BUD, 33L + k, 4, 1)
}
# self-checks: raw-data tests, so display rounding cannot trip them. Pivot total = largest number on its Grand Total row.
write_cell(ss, T_BUD, 44, 2, "Self-checks (live): every line should read OK")
write_cell(ss, T_BUD, 45, 2, "Check"); write_cell(ss, T_BUD, 45, 6, "Result"); write_cell(ss, T_BUD, 45, 7, "Status")
chk <- list(
  list("Every Expense row this month sits in a budgeted category (difference in $)",
       '=ROUND(SUMIFS(txn_amt,txn_type,"Expense",txn_month,month_start)-SUM($D$6:$D$14),2)'),
  list("Pivot table total equals Trends 12-month spending (difference in $)",
       '=ROUND(IFERROR(MAX(INDEX(Trends!$B$24:$Q$40,MATCH("Grand Total",Trends!$B$24:$B$40,0),0)),0)-Trends!$D$18,2)'),
  list("Transactions dated outside the 12 months (count; move the window with the first month on Lists)",
       '=COUNTIFS(txn_date,"<"&Lists!$B$5)+COUNTIFS(txn_date,">="&EDATE(Lists!$B$16,1))'),
  list("Rows whose Type does not match their Category (count)",
       '=COUNTA(txn_type)-SUMPRODUCT(COUNTIFS(txn_type,Lists!$E$5:$E$16,txn_cat,Lists!$D$5:$D$16))'))
for (k in seq_along(chk)) {
  write_cell(ss, T_BUD, 45L + k, 2, chk[[k]][[1]]); write_cell(ss, T_BUD, 45L + k, 6, chk[[k]][[2]])
  write_cell(ss, T_BUD, 45L + k, 7, sprintf('=IF(F%d=0,"OK","Check")', 45L + k))
}
write_cell(ss, T_BUD, 50, 2, "All checks")
write_cell(ss, T_BUD, 50, 6, '=COUNTIF(G46:G49,"OK")&" of 4"')
write_cell(ss, T_BUD, 50, 7, '=IF(COUNTIF(G46:G49,"OK")=4,"All pass","Review")')

# -- Net Worth (rows 6-17 months) --
write_cell(ss, T_NW, 2, 2, "Net worth")
write_cell(ss, T_NW, 3, 2, "Month-end balances (sample data). Blue cells are inputs: type your own balances and the totals, changes and charts follow. Investments and retirement also grow with market gains and employer contributions that Transactions does not show.")
write_cell(ss, T_NW, 4, 3, "ASSETS"); write_cell(ss, T_NW, 4, 8, "LIABILITIES"); write_cell(ss, T_NW, 4, 12, "NET WORTH")
hdr_n <- c("Month", "Checking", "Savings", "Investments", "Retirement", "Total assets", "Credit card",
           "Car loan", "Student loan", "Total liabilities", "Net worth", "Change vs last month", "Change %", "Axis label")
for (j in seq_along(hdr_n)) write_cell(ss, T_NW, 5, 1L + j, hdr_n[j])
for (i in seq_len(N_MONTHS)) {
  r <- 5L + i
  write_cell(ss, T_NW, r, 2, sprintf("=Lists!$B%d", mrow(i)))
  vals <- c(nw$Checking[i], nw$Savings[i], nw$Investments[i], nw$Retirement[i])
  for (j in 1:4) write_cell(ss, T_NW, r, 2L + j, vals[j])
  write_cell(ss, T_NW, r, 7, sprintf("=SUM(C%d:F%d)", r, r))
  libs <- c(nw$CreditCard[i], nw$CarLoan[i], nw$StudentLoan[i])
  for (j in 1:3) write_cell(ss, T_NW, r, 7L + j, libs[j])
  write_cell(ss, T_NW, r, 11, sprintf("=SUM(H%d:J%d)", r, r))
  write_cell(ss, T_NW, r, 12, sprintf("=G%d-K%d", r, r))
  if (i > 1) { write_cell(ss, T_NW, r, 13, sprintf("=L%d-L%d", r, r - 1)); write_cell(ss, T_NW, r, 14, f_safe_div(sprintf("M%d", r), sprintf("L%d", r - 1))) }
  else { write_cell(ss, T_NW, r, 13, "–"); write_cell(ss, T_NW, r, 14, "–") }
  # chart axis label, text so every month is labelled: month name, year on the first month and each January; picked month gets a dot
  write_cell(ss, T_NW, r, 15, sprintf('=TEXT($B%d,"mmm")&IF(OR(MONTH($B%d)=1,$B%d=MIN($B$6:$B$17))," "&TEXT($B%d,"yyyy"),"")&IF($B%d=month_start," ●","")', r, r, r, r, r))
}

# -- Trends (rows 6-17 months, 18 total, 19 average; pivot from row 24) --
write_cell(ss, T_TRD, 2, 2, "Trends")
write_cell(ss, T_TRD, 3, 2, "Twelve months of cash flow, plus a native pivot table of spending by category and month. Everything here is a formula or pivot over Transactions, so there are no blue input cells.")
for (j in 1:6) write_cell(ss, T_TRD, 5, 1L + j, c("Month", "Income", "Spending", "Savings", "Savings rate", "Axis label")[j])
for (i in seq_len(N_MONTHS)) {
  r <- 5L + i
  write_cell(ss, T_TRD, r, 2, sprintf("=Lists!$B%d", mrow(i)))
  write_cell(ss, T_TRD, r, 3, sprintf('=SUMIFS(txn_amt,txn_type,"Income",txn_month,$B%d)', r))
  write_cell(ss, T_TRD, r, 4, sprintf('=SUMIFS(txn_amt,txn_type,"Expense",txn_month,$B%d)', r))
  write_cell(ss, T_TRD, r, 5, sprintf("=C%d-D%d", r, r))
  write_cell(ss, T_TRD, r, 6, f_safe_div(sprintf("E%d", r), sprintf("C%d", r)))
  write_cell(ss, T_TRD, r, 7, sprintf('=TEXT($B%d,"mmm")&IF(OR(MONTH($B%d)=1,$B%d=MIN($B$6:$B$17))," "&TEXT($B%d,"yyyy"),"")&IF($B%d=month_start," ●","")', r, r, r, r, r))
}
write_cell(ss, T_TRD, 18, 2, "12-month total")
for (cl in c("C", "D", "E")) write_cell(ss, T_TRD, 18, match(cl, LETTERS), sprintf("=SUM(%s6:%s17)", cl, cl))
write_cell(ss, T_TRD, 18, 6, f_safe_div("E18", "C18"))
write_cell(ss, T_TRD, 19, 2, "Monthly average")
for (cl in c("C", "D", "E")) write_cell(ss, T_TRD, 19, match(cl, LETTERS), sprintf("=AVERAGE(%s6:%s17)", cl, cl))
write_cell(ss, T_TRD, 22, 2, "Spending by category and month (native pivot table of every Expense row in Transactions)")
# The note sits ABOVE the pivot (row 23) so the pivot can grow downward without ever running into it.
write_cell(ss, T_TRD, 23, 2, "Each row is shaded on its own scale (darker = that category's busiest months). Housing is a fixed cost, so it is left unshaded.")

# -- Dashboard --
write_cell(ss, T_DASH, 2, 2, "Personal Finance Tracker")
write_cell(ss, T_DASH, 2, 10, "SAMPLE DATA")
write_cell(ss, T_DASH, 2, 14, "Select month ▸")
write_cell(ss, T_DASH, 2, 17, as.character(months[SELECTED]))
# one-sentence takeaway for the selected month (over-budget list capped at 3 names so it stays on one line)
is_over  <- sprintf('(Budget!$G$6:$G$14="%s")+ISNUMBER(Budget!$G$6:$G$14)*(Budget!$G$6:$G$14>1)', NO_BUD)   # over 100%, or spending with no budget
over_n   <- paste0('SUMPRODUCT(', is_over, ')')
over_who <- paste0('IFERROR(TEXTJOIN(", ",TRUE,FILTER(Budget!$B$6:$B$14,', is_over, ')),"")')
write_cell(ss, T_DASH, 3, 2, paste0('=LET(n,', over_n, ',who,', over_who, ',"Showing "&month_label&" · "&IF(n=0,"every category is within budget",',
  'IF(n>3,n&" categories are over budget","over budget: "&who))&" · savings rate "&TEXT(K6,"0%")&" vs "&TEXT(Budget!$C$20,"0%")&" goal")'))
write_cell(ss, T_DASH, 3, 15, "View only? File > Make a copy to use the picker")
kcol <- c(2L, 5L, 8L, 11L, 14L, 17L)
k_lab <- c("INCOME", "SPENDING", "SAVINGS", "SAVINGS RATE", "NET WORTH", "BUDGET USED")
for (k in 1:6) write_cell(ss, T_DASH, 5, kcol[k], k_lab[k])
prior <- function(rng, tab = "Trends", key = "$B$6:$B$17") sprintf("SUMIFS(%s!%s,%s!%s,prev_start)", tab, rng, tab, key)
first <- 'COUNTIF(Trends!$B$6:$B$17,prev_start)=0'
write_cell(ss, T_DASH, 6, 2, "=Budget!$D$18")
write_cell(ss, T_DASH, 6, 5, "=Budget!$D$15")
write_cell(ss, T_DASH, 6, 8, "=B6-E6")
write_cell(ss, T_DASH, 6, 11, "=IFERROR(H6/B6,0)")
write_cell(ss, T_DASH, 6, 14, "=SUMIFS('Net Worth'!$L$6:$L$17,'Net Worth'!$B$6:$B$17,month_start)")
write_cell(ss, T_DASH, 6, 17, "=IFERROR(Budget!$D$15/Budget!$C$15,0)")
pct_sub <- function(cell, rng) paste0('=IF(', first, ',"first month in sample",LET(p,', prior(rng),
  ',IF(p=0,"no data last month",IF(', cell, '>=p,"\u25b2 ","\u25bc ")&TEXT(ABS(', cell, '/p-1),"0.0%")&" vs last month")))')
usd_sub <- function(cell, rng, tab = "Trends", key = "$B$6:$B$17") paste0('=IF(COUNTIF(', tab, '!', key,
  ',prev_start)=0,"first month in sample",LET(p,', prior(rng, tab, key),
  ',IF(', cell, '>=p,"\u25b2 ","\u25bc ")&TEXT(ABS(', cell, '-p),"$#,##0")&" vs last month"))')
write_cell(ss, T_DASH, 7, 2, pct_sub("B6", "$C$6:$C$17"))
write_cell(ss, T_DASH, 7, 5, pct_sub("E6", "$D$6:$D$17"))
write_cell(ss, T_DASH, 7, 8, usd_sub("H6", "$E$6:$E$17"))
write_cell(ss, T_DASH, 7, 11, '="Goal "&TEXT(Budget!$C$20,"0%")&IF(K6>=Budget!$C$20," · on track"," · below goal")')
write_cell(ss, T_DASH, 7, 14, usd_sub("N6", "$L$6:$L$17", "'Net Worth'", "$B$6:$B$17"))
write_cell(ss, T_DASH, 7, 17, '=TEXT(Budget!$D$15,"$#,##0")&" of "&TEXT(Budget!$C$15,"$#,##0")&" budget"')
write_cell(ss, T_DASH, 9, 2, "Budget health")
write_cell(ss, T_DASH, 9, 10, '="green: under "&TEXT(warn_at,"0%")&" of budget  ·  amber: "&TEXT(warn_at,"0%")&" to 100%  ·  red: over budget, or spending with no budget"')
for (i in 1:9) {
  c1 <- 2L + 2L * (i - 1L)
  write_cell(ss, T_DASH, 10, c1, sprintf("=Budget!$B%d", 5L + i))
  write_cell(ss, T_DASH, 11, c1, sprintf("=Budget!$G%d", 5L + i))
}
R_TOP <- 45L                                   # Top-5 panel title row
write_cell(ss, T_DASH, R_TOP, 2, '="Top 5 spending categories  ·  "&month_label')
write_cell(ss, T_DASH, R_TOP, 11, "About this sample")
write_cell(ss, T_DASH, R_TOP, 17, '=IF(Budget!$G$50="All pass","✓ self-checks pass","⚠ see Budget checks")')
for (j in list(c(2, "#"), c(3, "Category"), c(6, "Spent"), c(8, "Share"), c(9, "")))
  write_cell(ss, T_DASH, R_TOP + 1L, as.integer(j[1]), j[2])
for (k in 1:6) {
  r <- R_TOP + 1L + k
  write_cell(ss, T_DASH, r, 2, if (k <= 5) k else "•")
  write_cell(ss, T_DASH, r, 3, sprintf("=Budget!$B$%d", 24L + k))
  # whole dollars that add up: top 5 rounded; "everything else" is Budget!C30 (the rounded total minus those)
  write_cell(ss, T_DASH, r, 6, if (k <= 5) sprintf("=ROUND(Budget!$C$%d,0)", 24L + k) else "=Budget!$C$30")
  write_cell(ss, T_DASH, r, 8, sprintf("=IFERROR(F%d/$F$%d,0)", r, R_TOP + 8L))
  bar <- f_sparkline(sprintf("H%d", r), list(charttype = "bar", max = I(sprintf("$H$%d", R_TOP + 2L)),
           color1 = paste0("#", unname(PAL[c("blue", "teal", "amber", "violet", "sky", "slate")])[k])))
  write_cell(ss, T_DASH, r, 9, sprintf('=IF($H$%d=0,"",%s)', R_TOP + 2L, fraw(bar)))
}
write_cell(ss, T_DASH, R_TOP + 8L, 3, "Total spending")
write_cell(ss, T_DASH, R_TOP + 8L, 6, sprintf("=SUM(F%d:F%d)", R_TOP + 2L, R_TOP + 7L))
write_cell(ss, T_DASH, R_TOP + 8L, 8, sprintf("=SUM(H%d:H%d)", R_TOP + 2L, R_TOP + 7L))
about <- c("Sample data: all numbers are synthetic. No real people, merchants or accounts.",
           "Built with the r-googlesheets4 skill (github.com/salvadoraveldano/r-googlesheets4)",
           "Built on googlesheets4 by Jennifer Bryan and Posit (googlesheets4.tidyverse.org)",
           "How to use: pick a month at the top, then edit the blue cells on any tab.",
           "Input", "Formula", "Month picker: updates the cards, health strip, doughnut, budget chart and top 5. The trend charts show all 12 months (picked month marked ●).")
for (k in seq_along(about)) write_cell(ss, T_DASH, R_TOP + 1L + k, 11, about[k])
write_cell(ss, T_DASH, R_TOP + 6L, 13, "Blue text, often on pale yellow: a value you can change.")
write_cell(ss, T_DASH, R_TOP + 7L, 13, "Black text: a formula. Editing it shows a warning.")

flush_writes(ss, strict = TRUE)

# =============================================================================
# Formatting, one batch per tab (strict: stops on any HTTP error)
# =============================================================================
# Layout helpers: the skill's style presets (STYLE_BODY, STYLE_TITLE, STYLE_BRAND_SECTION_HEADER) with this sheet's sizes.
body_all <- function(sid, nr, nc) apply_style(sid, 1, nr, 1, nc, STYLE_BODY, font_color = COL_INK)
title_rows <- function(b, sid, last_col, title_h = 38L) {
  b$push(apply_style(sid, 2, 2, 2, last_col, STYLE_TITLE, font_size = 22, font_color = COL_INK))
  b$push(fmt_cells(sid, 3, 3, 2, last_col, font_size = 10, font_color = COL_SLATE, valign = "MIDDLE"))
  b$push(fmt_row_height(sid, 1, 1, 8L)); b$push(fmt_row_height(sid, 2, 2, title_h)); b$push(fmt_row_height(sid, 3, 3, 22L))
}
header_row <- function(b, sid, r, c1, c2, h = 34L, fill = COL_BRAND) {
  b$push(apply_style(sid, r, r, c1, c2, STYLE_BRAND_SECTION_HEADER, bg_color = fill, font_size = 10,
                     halign = "CENTER", wrap = TRUE))
  b$push(fmt_row_height(sid, r, r, h))
}
input_cells <- function(b, sid, r1, r2, c1, c2, ...) {
  b$push(fmt_cells(sid, r1, r2, c1, c2, font_color = COL_INPUT_FG, bg_color = COL_INPUT_BG, ...))
  b$push(fmt_borders(sid, r1, r2, c1, c2, inner_h = list(style = "SOLID", color = COL_WHITE),
                     inner_v = list(style = "SOLID", color = COL_WHITE)))
}

# ---- Lists ----
b <- new_batch()
b$push(body_all(S_LST, 40, 14)); title_rows(b, S_LST, 12)
b$push(fmt_col_widths(S_LST, c(16, 140, 24, 130, 80, 24, 120, 24, 90, 24, 130, 160)))
header_row(b, S_LST, 4, 2, 2); header_row(b, S_LST, 4, 4, 5); header_row(b, S_LST, 4, 7, 7)
header_row(b, S_LST, 4, 9, 9); header_row(b, S_LST, 4, 11, 12)
b$push(fmt_cells(S_LST, 4, 4, 2, 12, halign = "LEFT"))
b$push(fmt_cells(S_LST, 5, 16, 2, 2, numfmt = NF_MONTH_LONG, halign = "LEFT"))
input_cells(b, S_LST, 5, 5, 2, 2, bold = TRUE, numfmt = NF_MONTH_LONG, halign = "LEFT")   # first month: the one input
b$push(fmt_cells(S_LST, 5, 7, 11, 12, font_color = COL_SLATE, halign = "LEFT"))
b$push(fmt_cells(S_LST, 5, 5, 12, 12, numfmt = NF_DAY))
b$push(fmt_cells(S_LST, 6, 6, 12, 12, numfmt = NF_DAY))
b$push(fmt_cells(S_LST, 9, 9, 11, 11, font_size = 9, italic = TRUE, font_color = COL_SLATE))
b$push(fmt_tab_color(S_LST, hex_to_color(PAL[["slate"]])))
b$push(fmt_freeze(S_LST, rows = 4))
b$push(fmt_gridlines(S_LST, show = TRUE))
batch_format(ss, b$get(), strict = TRUE)

# ---- Transactions ----
b <- new_batch()
b$push(body_all(S_TXN, LAST_ROW, 10)); title_rows(b, S_TXN, 8)
b$push(fmt_col_widths(S_TXN, c(16, 110, 200, 120, 110, 100, 90, 100)))
header_row(b, S_TXN, 4, 2, 8, h = 30L)
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 2, 2, numfmt = NF_DAY, halign = "LEFT"))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 3, 5, halign = "LEFT"))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 6, 6, numfmt = NF_USD2, halign = "RIGHT"))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 7, 7, halign = "CENTER"))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 8, 8, numfmt = NF_MONTH, halign = "LEFT", font_color = COL_SLATE))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 2, 7, font_color = COL_INPUT_FG))      # typed-in columns: blue, also on rows you add
b$push(fmt_cells(S_TXN, 4, 4, 2, 5, halign = "LEFT")); b$push(fmt_cells(S_TXN, 4, 4, 6, 6, halign = "RIGHT")); b$push(fmt_cells(S_TXN, 4, 4, 7, 7, halign = "CENTER")); b$push(fmt_cells(S_TXN, 4, 4, 8, 8, halign = "LEFT"))
b$push(fmt_tab_color(S_TXN, hex_to_color(PAL[["teal"]])))
b$push(fmt_freeze(S_TXN, rows = 4)); b$push(fmt_gridlines(S_TXN, show = TRUE))
batch_format(ss, b$get(), strict = TRUE)

# ---- Budget ----
b <- new_batch()
b$push(body_all(S_BUD, 55, 12)); title_rows(b, S_BUD, 9)
b$push(fmt_col_widths(S_BUD, c(16, 170, 110, 110, 110, 100, 80, 190, 120, 16)))
header_row(b, S_BUD, 5, 2, 9, h = 32L)
b$push(fmt_cells(S_BUD, 5, 5, 2, 2, halign = "LEFT")); b$push(fmt_cells(S_BUD, 5, 5, 3, 7, halign = "RIGHT"))
# tight rows so the first printed landscape page ends after the top-5 chart-data block (no orphaned "Everything else" row on page 2)
b$push(fmt_row_height(S_BUD, 4, 4, 12L)); b$push(fmt_row_height(S_BUD, 6, 15, 24L)); b$push(fmt_row_height(S_BUD, 16, 16, 10L))
b$push(fmt_cells(S_BUD, 6, 15, 3, 3, numfmt = NF_USD, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 6, 15, 4, 5, numfmt = NF_USD2C, halign = "RIGHT"))   # cents: the column adds up exactly
b$push(fmt_cells(S_BUD, 6, 15, 6, 7, numfmt = NF_PCT1, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 6, 15, 9, 9, halign = "CENTER", bold = TRUE, font_size = 10))
b$push(fmt_borders(S_BUD, 6, 15, 2, 9, inner_h = list(style = "SOLID", color = COL_HAIR),
                   bottom = list(style = "SOLID", color = COL_HAIR)))
input_cells(b, S_BUD, 6, 14, 3, 3, numfmt = NF_USD, halign = "RIGHT")
b$push(apply_style(S_BUD, 15, 15, 2, 9, STYLE_BRAND_SUBTOTAL, font_size = 11))   # 11: back from the status column's 10
b$push(fmt_borders(S_BUD, 15, 15, 2, 9, top = list(style = "SOLID", color = COL_BRAND)))
header_row(b, S_BUD, 17, 2, 6, h = 26L, fill = COL_BRAND_DEEP)
b$push(fmt_cells(S_BUD, 17, 17, 2, 2, halign = "LEFT")); b$push(fmt_cells(S_BUD, 17, 17, 3, 6, halign = "RIGHT"))
b$push(fmt_row_height(S_BUD, 18, 21, 24L)); b$push(fmt_row_height(S_BUD, 22, 22, 12L)); b$push(fmt_row_height(S_BUD, 23, 23, 18L))
b$push(fmt_cells(S_BUD, 18, 19, 3, 3, numfmt = NF_USD, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 18, 19, 4, 5, numfmt = NF_USD2C, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 18, 19, 6, 6, numfmt = NF_PCT1, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 20, 20, 3, 4, numfmt = NF_PCT1, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 20, 20, 5, 5, numfmt = NF_PTS, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 18, 21, 2, 2, bold = TRUE))
b$push(fmt_cells(S_BUD, 21, 21, 4, 4, font_size = 9, italic = TRUE, font_color = COL_SLATE, halign = "LEFT"))
b$push(fmt_borders(S_BUD, 18, 21, 2, 6, inner_h = list(style = "SOLID", color = COL_HAIR), bottom = list(style = "SOLID", color = COL_HAIR)))
input_cells(b, S_BUD, 18, 18, 3, 3, numfmt = NF_USD, halign = "RIGHT")
input_cells(b, S_BUD, 20, 21, 3, 3, numfmt = NF_PCT0, halign = "RIGHT")   # savings goal, warning threshold
b$push(fmt_cells(S_BUD, 23, 23, 2, 2, font_size = 10, bold = TRUE, font_color = COL_SLATE))
header_row(b, S_BUD, 24, 2, 3, h = 24L, fill = hex_to_color(PAL[["slate"]]))
b$push(fmt_row_height(S_BUD, 25, 30, 18L))
b$push(fmt_cells(S_BUD, 24, 24, 2, 2, halign = "LEFT")); b$push(fmt_cells(S_BUD, 24, 24, 3, 3, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 25, 30, 3, 3, numfmt = NF_USD, halign = "RIGHT", font_color = COL_SLATE))
b$push(fmt_cells(S_BUD, 25, 30, 2, 2, font_color = COL_SLATE))
# chart data 2 (sorted % used) and the self-checks block
b$push(fmt_row_height(S_BUD, 31, 31, 14L)); b$push(fmt_row_height(S_BUD, 32, 32, 20L)); b$push(fmt_row_height(S_BUD, 34, 42, 18L))
b$push(fmt_cells(S_BUD, 32, 32, 2, 2, font_size = 10, bold = TRUE, font_color = COL_SLATE))
header_row(b, S_BUD, 33, 2, 4, h = 32L, fill = hex_to_color(PAL[["slate"]]))
b$push(fmt_cells(S_BUD, 33, 33, 2, 2, halign = "LEFT")); b$push(fmt_cells(S_BUD, 33, 33, 3, 4, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 34, 42, 3, 4, numfmt = NF_PCT0, halign = "RIGHT", font_color = COL_SLATE))
b$push(fmt_cells(S_BUD, 34, 42, 2, 2, font_color = COL_SLATE))
b$push(fmt_row_height(S_BUD, 43, 43, 14L)); b$push(fmt_row_height(S_BUD, 44, 44, 20L))
b$push(fmt_cells(S_BUD, 44, 44, 2, 2, font_size = 10, bold = TRUE, font_color = COL_SLATE))
header_row(b, S_BUD, 45, 2, 8, h = 24L, fill = hex_to_color(PAL[["slate"]]))
b$push(fmt_merge(S_BUD, 45, 45, 2, 5)); b$push(fmt_merge(S_BUD, 45, 45, 7, 8))
b$push(fmt_cells(S_BUD, 45, 45, 2, 2, halign = "LEFT")); b$push(fmt_cells(S_BUD, 45, 45, 6, 6, halign = "RIGHT"))
b$push(fmt_row_height(S_BUD, 46, 49, 32L)); b$push(fmt_row_height(S_BUD, 50, 50, 26L))
for (r in 46:50) { b$push(fmt_merge(S_BUD, r, r, 2, 5)); b$push(fmt_merge(S_BUD, r, r, 7, 8)) }
b$push(fmt_cells(S_BUD, 46, 50, 2, 8, valign = "MIDDLE"))
b$push(fmt_cells(S_BUD, 46, 49, 2, 5, font_size = 10, wrap = TRUE, valign = "MIDDLE", halign = "LEFT"))
b$push(fmt_cells(S_BUD, 46, 47, 6, 6, numfmt = NF_USD2, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 48, 50, 6, 6, numfmt = NF_INT, halign = "RIGHT"))
b$push(fmt_cells(S_BUD, 46, 50, 7, 8, bold = TRUE, font_size = 10, halign = "CENTER"))
b$push(fmt_cells(S_BUD, 50, 50, 2, 6, bold = TRUE))
b$push(fmt_borders(S_BUD, 46, 50, 2, 8, inner_h = list(style = "SOLID", color = COL_HAIR), bottom = list(style = "SOLID", color = COL_HAIR)))
b$push(fmt_tab_color(S_BUD, hex_to_color(PAL[["amber"]])))
b$push(fmt_freeze(S_BUD, rows = 5)); b$push(fmt_gridlines(S_BUD, show = FALSE))
batch_format(ss, b$get(), strict = TRUE)

# ---- Net Worth ----
b <- new_batch()
b$push(body_all(S_NW, 45, 17)); title_rows(b, S_NW, 14)
b$push(fmt_col_widths(S_NW, c(16, 96, 98, 98, 104, 104, 108, 96, 90, 96, 112, 112, 112, 84, 96, 16)))
for (g in list(list(3, 7, PAL[["teal"]], COL_WHITE), list(8, 11, PAL[["amber"]], COL_INK), list(12, 14, PAL[["blue"]], COL_WHITE))) {
  b$push(fmt_merge(S_NW, 4, 4, g[[1]], g[[2]]))
  b$push(fmt_cells(S_NW, 4, 4, g[[1]], g[[2]], font_size = 10, bold = TRUE, font_color = g[[4]], bg_color = hex_to_color(g[[3]]), halign = "CENTER", valign = "MIDDLE"))
}
b$push(fmt_row_height(S_NW, 4, 4, 24L))
header_row(b, S_NW, 5, 2, 15, h = 38L, fill = COL_BRAND_SUBTLE)
b$push(fmt_cells(S_NW, 5, 5, 2, 15, font_size = 10, font_color = COL_INK, bold = TRUE))
b$push(fmt_cells(S_NW, 5, 5, 2, 2, halign = "LEFT")); b$push(fmt_cells(S_NW, 5, 5, 3, 14, halign = "RIGHT")); b$push(fmt_cells(S_NW, 5, 5, 15, 15, halign = "LEFT"))
b$push(fmt_row_height(S_NW, 6, 17, 26L))
b$push(fmt_cells(S_NW, 6, 17, 2, 2, numfmt = NF_MONTH, halign = "LEFT", bold = TRUE))
b$push(fmt_cells(S_NW, 6, 17, 3, 12, numfmt = NF_USD_NEG, halign = "RIGHT"))   # chart sources: axis reads $0, not "-"
b$push(fmt_cells(S_NW, 6, 17, 13, 13, numfmt = NF_USD, halign = "RIGHT"))
b$push(fmt_cells(S_NW, 6, 17, 14, 14, numfmt = NF_PCT1, halign = "RIGHT"))
b$push(fmt_cells(S_NW, 6, 17, 15, 15, font_size = 9, font_color = COL_SLATE, halign = "LEFT"))
b$push(fmt_borders(S_NW, 6, 17, 2, 14, inner_h = list(style = "SOLID", color = COL_HAIR), bottom = list(style = "SOLID", color = COL_HAIR)))
input_cells(b, S_NW, 6, 17, 3, 6, numfmt = NF_USD_NEG, halign = "RIGHT")
input_cells(b, S_NW, 6, 17, 8, 10, numfmt = NF_USD_NEG, halign = "RIGHT")
b$push(fmt_cells(S_NW, 6, 17, 7, 7, bold = TRUE, bg_color = COL_BRAND_SUBTLE))
b$push(fmt_cells(S_NW, 6, 17, 11, 11, bold = TRUE, bg_color = COL_BRAND_SUBTLE))
b$push(fmt_cells(S_NW, 6, 17, 12, 12, bold = TRUE, font_size = 12, bg_color = COL_BRAND_SUBTLE))
b$push(fmt_row_height(S_NW, 19, 36, 21L))
b$push(fmt_tab_color(S_NW, hex_to_color(PAL[["violet"]])))
b$push(fmt_freeze(S_NW, rows = 5)); b$push(fmt_gridlines(S_NW, show = FALSE))
batch_format(ss, b$get(), strict = TRUE)

# ---- Trends ----
b <- new_batch()
b$push(body_all(S_TRD, 45, 17)); title_rows(b, S_TRD, 14)
b$push(fmt_col_widths(S_TRD, c(16, 128, rep(80, 12), 104, 16)))      # C..N months, O = Grand Total
header_row(b, S_TRD, 5, 2, 7)
b$push(fmt_cells(S_TRD, 5, 5, 2, 2, halign = "LEFT")); b$push(fmt_cells(S_TRD, 5, 5, 3, 6, halign = "RIGHT")); b$push(fmt_cells(S_TRD, 5, 5, 7, 7, halign = "LEFT"))
b$push(fmt_row_height(S_TRD, 4, 4, 10L)); b$push(fmt_row_height(S_TRD, 20, 21, 10L)); b$push(fmt_row_height(S_TRD, 23, 23, 22L))
b$push(fmt_row_height(S_TRD, 6, 19, 24L))
b$push(fmt_cells(S_TRD, 6, 17, 2, 2, numfmt = NF_MONTH, halign = "LEFT", bold = TRUE))
b$push(fmt_cells(S_TRD, 6, 19, 3, 5, numfmt = NF_USD_NEG, halign = "RIGHT"))   # chart sources: axis reads $0, not "-"
b$push(fmt_cells(S_TRD, 6, 18, 6, 6, numfmt = NF_PCT1, halign = "RIGHT"))
b$push(fmt_cells(S_TRD, 6, 17, 7, 7, font_size = 9, font_color = COL_SLATE, halign = "LEFT"))
b$push(fmt_borders(S_TRD, 6, 17, 2, 6, inner_h = list(style = "SOLID", color = COL_HAIR)))
b$push(apply_style(S_TRD, 18, 19, 2, 6, STYLE_BRAND_SUBTOTAL))
b$push(fmt_borders(S_TRD, 18, 18, 2, 6, top = list(style = "SOLID", color = COL_BRAND)))
b$push(fmt_cells(S_TRD, 22, 22, 2, 2, font_size = 12, bold = TRUE, font_color = COL_INK))
b$push(fmt_row_height(S_TRD, 22, 22, 30L))
b$push(fmt_cells(S_TRD, 23, 23, 2, 2, font_size = 9, italic = TRUE, font_color = COL_SLATE, valign = "MIDDLE"))
b$push(fmt_borders(S_TRD, 22, 22, 2, 15, bottom = list(style = "SOLID_MEDIUM", color = COL_BRAND)))
b$push(fmt_tab_color(S_TRD, hex_to_color(PAL[["sky"]])))
b$push(fmt_freeze(S_TRD, rows = 3)); b$push(fmt_gridlines(S_TRD, show = FALSE))
batch_format(ss, b$get(), strict = TRUE)

# ---- Dashboard ----
R <- list(top = 1, title = 2, sub = 3, gap1 = 4, kl = 5, kv = 6, ks = 7, gap2 = 8, hh = 9, hn = 10, hp = 11,
          gap3 = 12, c1 = 13, c1e = 27, gap4 = 28, c2 = 29, c2e = 43, gap5 = 44)
b <- new_batch(); sd <- S_DASH
b$push(body_all(sd, 60, 20))
b$push(fmt_col_widths(sd, c(16, rep(60, 18), 16)))
for (rh in list(c(1, 1, 8), c(2, 2, 46), c(3, 3, 22), c(4, 4, 10), c(5, 5, 20), c(6, 6, 46), c(7, 7, 22), c(8, 8, 14),
                c(9, 9, 26), c(10, 10, 22), c(11, 11, 34), c(12, 12, 14), c(13, 27, 21), c(28, 28, 14), c(29, 43, 21), c(44, 44, 14),
                c(45, 45, 28), c(46, 46, 24), c(47, 52, 30), c(53, 53, 40), c(54, 60, 21)))
  b$push(fmt_row_height(sd, rh[1], rh[2], rh[3]))
# title, badge, month picker
b$push(fmt_merge(sd, 2, 2, 2, 9)); b$push(fmt_merge(sd, 2, 2, 10, 11)); b$push(fmt_merge(sd, 2, 2, 14, 16)); b$push(fmt_merge(sd, 2, 2, 17, 19))
b$push(apply_style(sd, 2, 2, 2, 9, STYLE_TITLE, font_size = 26, font_color = COL_INK))
b$push(fmt_cells(sd, 2, 2, 10, 11, font_size = 9, bold = TRUE, font_color = hex_to_color("8A5A00"), bg_color = COL_WARNING_SOFT, halign = "CENTER", valign = "MIDDLE"))
b$push(fmt_borders(sd, 2, 2, 10, 11, top = list(style = "SOLID_THICK", color = COL_WHITE), bottom = list(style = "SOLID_THICK", color = COL_WHITE)))
b$push(fmt_cells(sd, 2, 2, 14, 16, font_size = 10, bold = TRUE, font_color = COL_SLATE, halign = "RIGHT", valign = "MIDDLE"))
b$push(fmt_cells(sd, 2, 2, 17, 19, font_size = 15, bold = TRUE, font_color = COL_INPUT_FG, bg_color = COL_INPUT_BG, halign = "CENTER", valign = "MIDDLE",
          numfmt = NF_MONTH_LONG))
b$push(fmt_borders(sd, 2, 2, 17, 19, top = list(style = "SOLID_MEDIUM", color = COL_BRAND), bottom = list(style = "SOLID_MEDIUM", color = COL_BRAND),
                   left = list(style = "SOLID_MEDIUM", color = COL_BRAND), right = list(style = "SOLID_MEDIUM", color = COL_BRAND)))
b$push(fmt_cells(sd, 3, 3, 2, 19, font_size = 10, font_color = COL_SLATE, valign = "MIDDLE"))
b$push(fmt_merge(sd, 3, 3, 2, 14)); b$push(fmt_merge(sd, 3, 3, 15, 19))
b$push(fmt_cells(sd, 3, 3, 2, 14, font_size = 11, font_color = COL_INK, valign = "MIDDLE", halign = "LEFT"))        # headline
b$push(fmt_cells(sd, 3, 3, 15, 19, font_size = 9, italic = TRUE, font_color = COL_SLATE, valign = "MIDDLE", halign = "RIGHT"))   # view-only hint
# KPI cards
acc <- unname(PAL[c("blue", "amber", "teal", "violet", "navy", "sky")])
for (k in 1:6) {
  c1 <- kcol[k]; c2 <- c1 + 2L
  for (r in 5:7) b$push(fmt_merge(sd, r, r, c1, c2))
  b$push(fmt_cells(sd, 5, 7, c1, c2, bg_color = COL_PANEL, halign = "CENTER", valign = "MIDDLE"))
  b$push(fmt_cells(sd, 5, 5, c1, c2, font_size = 9, bold = TRUE, font_color = COL_SLATE))
  b$push(fmt_cells(sd, 6, 6, c1, c2, font_size = 26, bold = TRUE, font_color = COL_INK))
  b$push(fmt_cells(sd, 7, 7, c1, c2, font_size = 10, font_color = COL_SLATE))
  b$push(fmt_borders(sd, 5, 7, c1, c2, left = WHITE_THICK, right = WHITE_THICK))
  b$push(fmt_borders(sd, 5, 5, c1, c2, top = list(style = "SOLID_THICK", color = hex_to_color(acc[k]))))
}
for (cc in c(2, 5, 8, 14)) b$push(fmt_cells(sd, 6, 6, cc, cc + 2, numfmt = NF_USD_NEG))
for (cc in c(11, 17)) b$push(fmt_cells(sd, 6, 6, cc, cc + 2, numfmt = NF_PCT1))
# budget health strip
b$push(fmt_cells(sd, 9, 9, 2, 19, font_size = 12, bold = TRUE, font_color = COL_INK, valign = "MIDDLE"))
b$push(fmt_merge(sd, 9, 9, 10, 19))
b$push(fmt_cells(sd, 9, 9, 10, 19, font_size = 9, bold = FALSE, font_color = COL_SLATE, halign = "RIGHT"))
for (i in 1:9) {
  c1 <- 2L + 2L * (i - 1L); c2 <- c1 + 1L
  b$push(fmt_merge(sd, 10, 10, c1, c2)); b$push(fmt_merge(sd, 11, 11, c1, c2))
  b$push(fmt_cells(sd, 10, 11, c1, c2, bg_color = COL_PANEL, halign = "CENTER", valign = "MIDDLE"))
  b$push(fmt_cells(sd, 10, 10, c1, c2, font_size = 9, bold = TRUE))
  b$push(fmt_cells(sd, 11, 11, c1, c2, font_size = 14, bold = TRUE, numfmt = NF_PCT0))
  b$push(fmt_borders(sd, 10, 11, c1, c2, left = WHITE_THICK, right = WHITE_THICK))
}
# chart panels
for (pr in list(c(R$c1, R$c1e, 2, 10), c(R$c1, R$c1e, 11, 19), c(R$c2, R$c2e, 2, 10), c(R$c2, R$c2e, 11, 19))) {
  b$push(fmt_cells(sd, pr[1], pr[2], pr[3], pr[4], bg_color = COL_PANEL))
  b$push(fmt_borders(sd, pr[1], pr[2], pr[3], pr[4], left = WHITE_THICK, right = WHITE_THICK))
  b$push(fmt_borders(sd, pr[1], pr[1], pr[3], pr[4], top = list(style = "SOLID_THICK", color = COL_BRAND)))
}
# top 5 + about panels
rt <- R_TOP
for (pr in list(c(rt, rt + 8, 2, 10), c(rt, rt + 8, 11, 19))) {
  b$push(fmt_cells(sd, pr[1], pr[2], pr[3], pr[4], bg_color = COL_PANEL, valign = "MIDDLE"))
  b$push(fmt_borders(sd, pr[1], pr[2], pr[3], pr[4], left = WHITE_THICK, right = WHITE_THICK))
  b$push(fmt_borders(sd, pr[1], pr[1], pr[3], pr[4], top = list(style = "SOLID_THICK", color = COL_BRAND)))
  b$push(fmt_cells(sd, pr[1], pr[1], pr[3], pr[4], font_size = 12, bold = TRUE, font_color = COL_INK))
}
b$push(fmt_merge(sd, rt, rt, 17, 19))
b$push(fmt_cells(sd, rt, rt, 17, 19, font_size = 9, bold = TRUE, font_color = COL_SLATE, halign = "RIGHT"))        # self-check status
b$push(fmt_cells(sd, rt + 1, rt + 1, 2, 10, font_size = 9, bold = TRUE, font_color = COL_SLATE))
b$push(fmt_cells(sd, rt + 1, rt + 1, 6, 8, halign = "RIGHT"))
for (r in (rt + 2):(rt + 8)) { b$push(fmt_merge(sd, r, r, 3, 5)); b$push(fmt_merge(sd, r, r, 6, 7)); b$push(fmt_merge(sd, r, r, 9, 10)) }
b$push(fmt_merge(sd, rt + 1, rt + 1, 3, 5)); b$push(fmt_merge(sd, rt + 1, rt + 1, 6, 7)); b$push(fmt_merge(sd, rt + 1, rt + 1, 9, 10))
rank_bg <- unname(PAL[c("blue", "teal", "amber", "violet", "sky", "slate")])
rank_fg <- list(COL_WHITE, COL_INK, COL_INK, COL_WHITE, COL_INK, COL_INK)       # keep text readable on each fill
for (k in 1:6) b$push(fmt_cells(sd, rt + 1 + k, rt + 1 + k, 2, 2, bold = TRUE, font_color = rank_fg[[k]],
                         bg_color = hex_to_color(rank_bg[k]), halign = "CENTER"))
b$push(fmt_cells(sd, rt + 8, rt + 8, 2, 2, bg_color = COL_PANEL))
b$push(fmt_cells(sd, rt + 2, rt + 8, 3, 5, halign = "LEFT", font_size = 11))
b$push(fmt_cells(sd, rt + 2, rt + 8, 6, 7, numfmt = NF_USD, halign = "RIGHT", font_size = 11))
b$push(fmt_cells(sd, rt + 2, rt + 8, 8, 8, numfmt = NF_PCT0, halign = "RIGHT", font_color = COL_SLATE))
b$push(fmt_borders(sd, rt + 2, rt + 7, 2, 10, inner_h = list(style = "SOLID", color = COL_HAIR)))
b$push(fmt_cells(sd, rt + 8, rt + 8, 3, 8, bold = TRUE, font_color = COL_INK))   # back from the slate share column
b$push(fmt_borders(sd, rt + 8, rt + 8, 2, 10, top = list(style = "SOLID", color = COL_BRAND)))
for (r in c(rt + 2:5, rt + 8)) {
  b$push(fmt_merge(sd, r, r, 11, 19))
  b$push(fmt_cells(sd, r, r, 11, 19, font_size = 10, font_color = COL_SLATE, wrap = TRUE, valign = "MIDDLE", halign = "LEFT"))
}
for (r in c(rt + 6, rt + 7)) { b$push(fmt_merge(sd, r, r, 11, 12)); b$push(fmt_merge(sd, r, r, 13, 19))
  b$push(fmt_cells(sd, r, r, 13, 19, font_size = 10, font_color = COL_SLATE, valign = "MIDDLE", halign = "LEFT")) }
b$push(fmt_cells(sd, rt + 6, rt + 6, 11, 12, font_size = 10, bold = TRUE, font_color = COL_INPUT_FG, bg_color = COL_INPUT_BG, halign = "CENTER", valign = "MIDDLE"))
b$push(fmt_cells(sd, rt + 7, rt + 7, 11, 12, font_size = 10, bold = TRUE, font_color = COL_INK, bg_color = hex_to_color("E7EAF0"), halign = "CENTER", valign = "MIDDLE"))
b$push(fmt_borders(sd, rt + 6, rt + 7, 11, 12, inner_h = WHITE_THICK, top = WHITE_THICK, bottom = WHITE_THICK))
b$push(fmt_cells(sd, rt + 2, rt + 2, 11, 19, font_size = 10, font_color = COL_INK))
b$push(fmt_cells(sd, rt + 3, rt + 4, 11, 19, font_size = 10, font_color = COL_BRAND))          # the two link rows
b$push(fmt_tab_color(sd, COL_BRAND)); b$push(fmt_freeze(sd, rows = 3)); b$push(fmt_gridlines(sd, show = FALSE))
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# Conditional formatting (own batch per tab so one bad rule cannot sink the rest)
# =============================================================================
# b$cf() numbers the rules in listing order, so the first rule that matches wins.
b <- new_batch()
# A custom formula cannot name another tab, so the one threshold is read with INDIRECT: legend, bars, status and strip never drift.
WARN_REF <- 'INDIRECT("Budget!$C$21")'
for (rule in list(list(sprintf('=OR(B$11="%s",AND(ISNUMBER(B$11),B$11>1))', NO_BUD), BAD), list(paste0("=AND(ISNUMBER(B$11),B$11>=", WARN_REF, ")"), WARN), list("=ISNUMBER(B$11)", GOOD)))
  b$cf(fmt_cond_formula, S_DASH, 10, 11, 2, 19, rule[[1]], font_color = rule[[2]]$fg, bg_color = rule[[2]]$bg)
text_rule <- function(b, r, cc, op, text, color) b$cf(fmt_cond_text, S_DASH, r, r, cc, cc, op = op, text = text, font_color = color$fg, bold = TRUE)
for (cc in c(2, 8, 14)) { text_rule(b, 7, cc, "starts_with", "▲", GOOD); text_rule(b, 7, cc, "starts_with", "▼", BAD) }   # up is good: income, savings, net worth
text_rule(b, 7, 5, "starts_with", "▲", BAD); text_rule(b, 7, 5, "starts_with", "▼", GOOD)                              # spending up is bad
text_rule(b, 7, 11, "contains", "on track", GOOD); text_rule(b, 7, 11, "contains", "below goal", BAD)
b$cf(fmt_cond_formula, S_DASH, 7, 7, 17, 17, "=$Q$6>1", font_color = BAD$fg, bold = TRUE)
b$cf(fmt_cond_formula, S_DASH, 7, 7, 17, 17, paste0("=$Q$6>=", WARN_REF), font_color = WARN$fg, bold = TRUE)
b$cf(fmt_cond_formula, S_DASH, 7, 7, 17, 17, paste0("=$Q$6<", WARN_REF), font_color = GOOD$fg, bold = TRUE)
text_rule(b, R_TOP, 17, "starts_with", "✓", GOOD); text_rule(b, R_TOP, 17, "starts_with", "⚠", BAD)
b$cf(fmt_cond_number, S_DASH, 6, 6, 8, 8, 0, "less", font_color = BAD$fg)
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()
for (rg in list(c(6, 15, 5, 6), c(18, 19, 5, 6), c(20, 20, 5, 5))) {
  b$cf(fmt_cond_number, S_BUD, rg[1], rg[2], rg[3], rg[4], 0, "less", font_color = BAD$fg, bg_color = BAD$bg, bold = TRUE)
  b$cf(fmt_cond_number, S_BUD, rg[1], rg[2], rg[3], rg[4], 0, "greater_eq", font_color = GOOD$fg, bg_color = GOOD$bg)
}
b$cf(fmt_cond_text_equals, S_BUD, 6, 15, 9, 9, "Over budget", font_color = BAD$fg, bg_color = BAD$bg)
b$cf(fmt_cond_text_equals, S_BUD, 6, 15, 9, 9, "No budget", font_color = BAD$fg, bg_color = BAD$bg)
b$cf(fmt_cond_text_equals, S_BUD, 6, 15, 9, 9, "Close to limit", font_color = WARN$fg, bg_color = WARN$bg)
b$cf(fmt_cond_text_equals, S_BUD, 6, 15, 9, 9, "On track", font_color = GOOD$fg, bg_color = GOOD$bg)
for (ok in c("OK", "All pass")) b$cf(fmt_cond_text_equals, S_BUD, 46, 50, 7, 7, ok, font_color = GOOD$fg, bg_color = GOOD$bg)
for (no in c("Check", "Review")) b$cf(fmt_cond_text_equals, S_BUD, 46, 50, 7, 7, no, font_color = BAD$fg, bg_color = BAD$bg)
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()
b$cf(fmt_cond_number, S_NW, 7, 17, 13, 14, 0, "less", font_color = BAD$fg)
b$cf(fmt_cond_number, S_NW, 7, 17, 13, 14, 0, "greater_eq", font_color = GOOD$fg)
b$cf(fmt_cond_formula, S_NW, 6, 17, 2, 15, '=RIGHT($O6,1)="●"', bg_color = hex_to_color("EAF1FF"))
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()
b$cf(fmt_cond_formula, S_TRD, 6, 17, 2, 7, '=RIGHT($G6,1)="●"', bg_color = hex_to_color("EAF1FF"))
b$cf(fmt_cond_number, S_TRD, 6, 17, 5, 5, 0, "less", font_color = BAD$fg, bold = TRUE)
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()
b$cf(fmt_cond_formula, S_TXN, 5, LAST_ROW, 7, 7,                     # first, so it wins: Type must match the category's kind (Lists)
          '=AND($D5<>"",$G5<>"",$G5<>IFERROR(VLOOKUP($D5,INDIRECT("Lists!$D$5:$E$16"),2,FALSE),$G5))', font_color = BAD$fg, bg_color = BAD$bg, bold = TRUE)
b$cf(fmt_cond_text_equals, S_TXN, 5, LAST_ROW, 7, 7, "Income", font_color = GOOD$fg, bold = TRUE)
b$cf(fmt_cond_formula, S_TXN, 5, LAST_ROW, 6, 6, '=$G5="Income"', font_color = GOOD$fg)
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# Dropdowns, filter, banding
# =============================================================================
b <- new_batch()
b$push(fmt_dropdown_range(S_DASH, 2, 2, 17, 17, "=Lists!$B$5:$B$16"))
b$push(fmt_validation(S_LST, 5, 5, 2, 2, "CUSTOM_FORMULA", "=AND(ISNUMBER(B5),DAY(B5)=1)",
                      input_message = "Type the first day of the first month, for example 2025-10-01. The other eleven months follow."))
b$push(fmt_validation(S_BUD, 6, 14, 3, 3, "NUMBER_GREATER_THAN_EQ", 0,
                      input_message = "Enter a monthly budget of 0 or more. A category with a 0 budget shows as 'no budget' when you spend in it."))
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()
b$push(fmt_dropdown_range(S_TXN, 5, LAST_ROW, 4, 4, "=Lists!$D$5:$D$16"))
b$push(fmt_dropdown_range(S_TXN, 5, LAST_ROW, 5, 5, "=Lists!$G$5:$G$7"))
b$push(fmt_dropdown_range(S_TXN, 5, LAST_ROW, 7, 7, "=Lists!$I$5:$I$6"))
b$push(fmt_validation(S_TXN, 5, LAST_ROW, 6, 6, "NUMBER_GREATER", 0,
                      input_message = "Enter a positive amount. The Type column says whether it is income or an expense."))
b$push(fmt_validation(S_TXN, 5, LAST_ROW, 2, 2, "DATE_IS_VALID", input_message = "Enter a date, for example 2026-03-14."))
b$push(fmt_basic_filter(S_TXN, 4, LAST_ROW, 2, 7))   # B:G; column H is one array formula, sorting must not touch it
# Band only the used rows plus a margin: banding all the way to LAST_ROW prints as ~20 blank banded pages (rows added past the margin are just unbanded).
BAND_LAST <- 4L + nrow(txn) + 50L
b$push(fmt_banding(S_TXN, 4, BAND_LAST, 2, 8, header_color = COL_BRAND, first_band = COL_WHITE, second_band = COL_PANEL))
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# Native pivot table (spending by category x month) + heatmap
# =============================================================================
PIV_R <- 24L
pivot_req <- function() fmt_pivot_table(
  S_TRD, anchor_row = PIV_R, anchor_col = 2L,
  source_sheet_id = S_TXN, source_range = c(4L, LAST_ROW, 2L, 8L),              # B4:H1000, header on row 4
  rows    = list(list(sourceColumnOffset = 2L, showTotals = TRUE, sortOrder = "ASCENDING")),    # Category
  columns = list(list(sourceColumnOffset = 6L, showTotals = TRUE, sortOrder = "ASCENDING")),    # Month
  values  = list(list(sourceColumnOffset = 4L, summarizeFunction = "SUM", name = "Spent")),     # Amount
  filters = list("5" = list(visibleValues = list("Expense"))))                                   # Type = Expense
# A pivot filter that keeps it inside the 12-month window was tried (NUMBER_BETWEEN / DATE_BETWEEN on the Month
# column with sheet references): the API refused one and the other did not give the right total, so the pivot
# stays unfiltered. A row dated outside the 12 months then adds a column and pushes Grand Total right, so P:Q get
# a real width (never ###) and the Budget self-checks flag such a row.
batch_format(ss, list(pivot_req()), strict = TRUE)
pivot_total_ok <- function() {            # Grand Total row must hold the generated Expense total
  m <- read_values(ss, sprintf("'%s'!B%d:Q%d", T_TRD, PIV_R, PIV_R + 16L), "UNFORMATTED_VALUE")[[1]]
  hit <- if (nrow(m)) which(m[, 1] == "Grand Total") else integer()
  length(hit) == 1L && isTRUE(abs(max(suppressWarnings(as.numeric(m[hit, -1])), na.rm = TRUE) - sum(txn$Amount[txn$Type == "Expense"])) < 0.01)
}
# The pivot is computed server-side right after the request: retry once before calling it a failure.
if (!(pivot_total_ok() || { Sys.sleep(3); pivot_total_ok() }))
  stop("The Trends pivot table did not appear, or its Grand Total differs from the Expense total in Transactions. ",
       "Open the Trends tab, check the pivot around B24, and rebuild.", call. = FALSE)
batch_format(ss, list(fmt_col_width(S_TRD, 16, 17, 104L)), strict = TRUE)

# =============================================================================
# Charts (cross-tab sources; chart data sits in visible columns)
# =============================================================================
LBL_TRD <- c(5, 17, 7, 7); LBL_NW <- c(5, 17, 15, 15)      # text month labels ("Sep 2026 ●"): every month shown, picked one marked
MONTH_AXIS <- "Month (● = picked month)"
SIZE <- c(536L, 311L)                                         # the four Dashboard charts
# The builders read the data tab and anchor the chart on another (anchor_sheet_id); `style` is the shared look.
batch_format(ss, list(
  fmt_chart_pie(S_BUD, "Spending by category (top 5 + everything else)",
                domain_range = c(25, 30, 2, 2), data_range = c(25, 30, 3, 3), donut = TRUE,
                anchor = c(R$c1, 2L), size = SIZE, anchor_sheet_id = S_DASH, offset_y = 4L, style = CHART_STYLE),
  fmt_chart_basic(S_BUD, "Share of budget used, biggest first (100% = limit)", "COMBO",
                  domain_range = c(33, 42, 2, 2),
                  series_list = list(list(range = c(33, 42, 3, 3), color = hex_to_color(PAL[["blue"]]), type = "COLUMN"),
                                     list(range = c(33, 42, 4, 4), color = hex_to_color("E5484D"), type = "LINE",
                                          line = list(type = "MEDIUM_DASHED", width = 2))),
                  anchor = c(R$c1, 11L), size = SIZE, anchor_sheet_id = S_DASH, offset_x = 4L, offset_y = 4L,
                  y_title = "% of monthly budget (axis stops at 200%)", y_min = 0, y_max = 2, style = CHART_STYLE),
  # The savings-rate line sits on the right axis; Sheets drops a right-axis title, so the legend names it.
  fmt_chart_basic(S_TRD, "Income vs spending, with savings rate", "COMBO",
                  domain_range = LBL_TRD,
                  series_list = list(list(range = c(5, 17, 3, 3), color = hex_to_color(PAL[["blue"]]), type = "COLUMN"),
                                     list(range = c(5, 17, 4, 4), color = hex_to_color(PAL[["amber"]]), type = "COLUMN"),
                                     list(range = c(5, 17, 6, 6), color = hex_to_color(PAL[["teal"]]), type = "LINE", axis = "RIGHT_AXIS")),
                  anchor = c(R$c2, 2L), size = SIZE, anchor_sheet_id = S_DASH, offset_y = 4L,
                  x_title = MONTH_AXIS, y_title = "USD per month", style = CHART_STYLE),
  # COLUMN, not AREA: an area chart puts its last point on the plot edge and Sheets then drops that label at this width,
  # so the "Sep ●" marker the axis title promises never showed. Month-end balances are snapshots, so columns suit them.
  fmt_chart_basic(S_NW, "Net worth, month-end", "COLUMN",
                  domain_range = LBL_NW,
                  series_list = list(list(range = c(5, 17, 12, 12), color = hex_to_color(PAL[["blue"]]))),
                  anchor = c(R$c2, 11L), size = SIZE, anchor_sheet_id = S_DASH, offset_x = 4L, offset_y = 4L, legend = "NO_LEGEND",
                  x_title = MONTH_AXIS, y_title = "USD", style = CHART_STYLE),
  fmt_chart_basic(S_TRD, "Monthly savings (income minus spending)", "COLUMN",
                  domain_range = LBL_TRD,
                  series_list = list(list(range = c(5, 17, 5, 5), color = hex_to_color(PAL[["teal"]]))),
                  anchor = c(5L, 8L), size = c(640L, 356L), offset_x = 12L, legend = "NO_LEGEND",
                  x_title = MONTH_AXIS, y_title = "USD per month", style = CHART_STYLE),
  # Net Worth: teal family = assets (darkest at the bottom of the stack), amber = liabilities, blue = net worth
  fmt_chart_basic(S_NW, "Assets, liabilities and net worth", "LINE",
                  domain_range = LBL_NW,
                  series_list = list(list(range = c(5, 17, 7, 7), color = hex_to_color(PAL[["teal"]])),
                                     list(range = c(5, 17, 11, 11), color = hex_to_color(PAL[["amber"]])),
                                     list(range = c(5, 17, 12, 12), color = hex_to_color(PAL[["blue"]]))),
                  anchor = c(19L, 2L), size = c(696L, 330L), offset_y = 6L,
                  x_title = MONTH_AXIS, y_title = "USD", style = CHART_STYLE),
  fmt_chart_basic(S_NW, "Where the assets are", "AREA",
                  domain_range = LBL_NW,
                  series_list = lapply(3:6, function(cl) list(range = c(5, 17, cl, cl),
                                         color = hex_to_color(c("0B6E66", PAL[["teal"]], "5CC9BF", "A8E3DD")[cl - 2L]))),
                  anchor = c(19L, 9L), size = c(696L, 330L), offset_y = 6L, stacked_type = "STACKED",
                  x_title = MONTH_AXIS, y_title = "USD", style = CHART_STYLE)),
  strict = TRUE)

# =============================================================================
# Pivot look: read where it landed, then shade the body as a heatmap
# =============================================================================
pivot_labels <- function() { m <- read_values(ss, sprintf("'%s'!B%d:P%d", T_TRD, PIV_R, PIV_R + 16L))[[1]]; if (nrow(m)) m[, 1] else character() }
lab <- pivot_labels()
if (!all(CAT_EXP %in% lab)) { Sys.sleep(3); lab <- pivot_labels() }          # one retry, as above
r_first <- which(lab %in% CAT_EXP)[1]; r_last <- tail(which(lab %in% CAT_EXP), 1)
if (is.na(r_first) || r_last - r_first + 1L != length(CAT_EXP))
  stop("The Trends pivot does not list the ", length(CAT_EXP), " expense categories in one block (found rows ",
       r_first, " to ", r_last, " of the pivot).", call. = FALSE)
PIV_BODY <- c(PIV_R + r_first - 1L, PIV_R + r_last - 1L, 3L, 2L + N_MONTHS + 1L)   # rows, cols C..O
b <- new_batch()
b$push(fmt_cells(S_TRD, PIV_R, PIV_R + r_first - 2L, 2, 15, bold = TRUE, italic = FALSE, font_color = COL_INK, bg_color = COL_BRAND_SUBTLE, halign = "RIGHT"))   # italic = FALSE: Sheets italicises the pivot's own labels
b$push(fmt_cells(S_TRD, PIV_R, PIV_R + r_first - 2L, 2, 2, halign = "LEFT"))
b$push(fmt_cells(S_TRD, PIV_BODY[1], PIV_R + r_last, 2, 2, bold = TRUE, halign = "LEFT"))
b$push(fmt_cells(S_TRD, PIV_BODY[1], PIV_R + r_last, 3, 17, numfmt = NF_USD_NEG, halign = "RIGHT"))   # C:Q, so an extra month column is formatted too
b$push(fmt_cells(S_TRD, PIV_R + r_last, PIV_R + r_last, 2, 15, bold = TRUE, bg_color = COL_BRAND_SUBTLE))
b$push(fmt_cells(S_TRD, PIV_R, PIV_R + r_last, 15, 15, bold = TRUE))
b$push(fmt_row_height(S_TRD, PIV_R, PIV_R + r_last, 22L))
# One colour scale per category row, so each shows its own busy months (Travel in Dec, Jun, Mar). A single scale
# over all rows is washed out by the rent. Housing is a fixed cost, so it stays unshaded.
for (cat in setdiff(CAT_EXP, "Housing"))
  b$cf(fmt_cond_color_scale, S_TRD, PIV_R + match(cat, lab) - 1L, PIV_R + match(cat, lab) - 1L, 3L, 2L + N_MONTHS,
       min_color = COL_WHITE, mid_color = hex_to_color("FDE8B6"), max_color = hex_to_color("F5B84A"))
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# Protection (warning-only: anyone can still edit after a prompt) and the two real links
# =============================================================================
batch_format(ss, list(
  fmt_protected_range(S_DASH, description = "Formulas and layout. Only the month picker is meant to be changed.",
                      unprotected_ranges = list(grid_range(S_DASH, 2, 2, 17, 19))),
  fmt_protected_range(S_BUD, description = "Formulas. Budgets, expected income, the savings goal and the warning threshold are open.",
                      unprotected_ranges = list(grid_range(S_BUD, 6, 14, 3, 3), grid_range(S_BUD, 18, 18, 3, 3), grid_range(S_BUD, 20, 21, 3, 3))),
  fmt_protected_range(S_NW, description = "Totals and net worth are formulas. Balances are open.",
                      unprotected_ranges = list(grid_range(S_NW, 6, 17, 3, 6), grid_range(S_NW, 6, 17, 8, 10))),
  fmt_protected_range(S_TRD, description = "Everything here is a formula or a pivot table."),
  fmt_protected_range(S_TXN, 4, LAST_ROW, 8, 8, description = "Month is a formula (one array formula in H5)."),
  fmt_protected_range(S_LST, 4, 7, 11, 12, description = "Derived from the Dashboard month picker."),
  fmt_protected_range(S_LST, 6, 16, 2, 2, description = "Formulas: the months follow the first month in B5."),
  fmt_protected_range(S_LST, 5, 16, 4, 5, description = "Renaming a category here breaks the Transactions rows that use the old name. Change both together.")),
  strict = TRUE)

batch_format(ss, list(link_cells_req(S_DASH, R_TOP + 3L, 11L,
  labels = about[2:3], urls = c("https://github.com/salvadoraveldano/r-googlesheets4", "https://googlesheets4.tidyverse.org"))),
  strict = TRUE)

# =============================================================================
# Self-checks: no error values anywhere, expected chart counts
# =============================================================================
vals <- read_values(ss, sprintf("'%s'!A1:Z%d", TABS, LAST_ROW))
err_pat <- "^#(REF!|DIV/0!|N/A|NAME\\?|VALUE!|NUM!|ERROR!|NULL!)|^Err:"
bad <- unlist(Map(function(tab, m) {
  hit <- m[grepl(err_pat, m)]
  if (length(hit)) paste0(tab, ": ", paste(unique(hit), collapse = ", ")) else NULL
}, TABS, vals))
if (length(bad)) stop("Error values found: ", paste(bad, collapse = " | "), call. = FALSE)
cnt <- gs_count_objects(ss)
n_ch <- setNames(cnt$charts, cnt$tab)
stopifnot(n_ch[[T_DASH]] == 4L, n_ch[[T_NW]] == 2L, n_ch[[T_TRD]] == 1L)
chk_now <- t(read_values(ss, sprintf("'%s'!F46:G50", T_BUD))[[1]])        # the sheet's own self-checks must pass on a fresh build
message("[personal-finance] self-checks on the Budget tab: ", paste(chk_now, collapse = " "))
stopifnot(identical(read_values(ss, sprintf("'%s'!G50", T_BUD))[[1]][1, 1], "All pass"))
stopifnot(length(audit_chart_sources(as.character(ss))) == 0L)           # no chart reads a hidden column, on any tab
message("[personal-finance] OK: no error values, charts per tab: ", paste(names(n_ch), n_ch, sep = "=", collapse = ", "))
message("[personal-finance] Sheet: https://docs.google.com/spreadsheets/d/", as.character(ss),
        "   (rebuild with SHEET_ID=", as.character(ss), ")")
