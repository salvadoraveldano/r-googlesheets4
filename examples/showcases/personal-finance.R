# =============================================================================
# personal-finance.R  -  Showcase: "Personal Finance Tracker - Sample Data"
# =============================================================================
# Builds     One Google Sheet with six tabs: Dashboard (month picker, KPI strip,
#            budget table, spending breakdown, 4 charts), Budget (inputs, SUMIFS
#            actuals, variance, live self-checks), Transactions (~370 rows,
#            dropdowns, filter), Net Worth (balances, totals, MoM, 2 charts),
#            Trends (12-month summary, savings chart, native pivot heatmap), Lists.
#            Styled with the skill's default "Ledger" design system.
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

# -- Names and number formats (colours, type and rules come from the Ledger tokens) --
T_DASH <- "Dashboard"; T_BUD <- "Budget"; T_TXN <- "Transactions"
T_NW <- "Net Worth"; T_TRD <- "Trends"; T_LST <- "Lists"
TABS <- c(T_DASH, T_BUD, T_TXN, T_NW, T_TRD, T_LST)

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
hx <- function(col) color_to_hex(col)       # "#RRGGBB", for SPARKLINE colours
GREY <- hex_to_color(CHART_PALETTE[2]); DARK <- hex_to_color(CHART_PALETTE[5])   # comparison and reference series

# A table's column-header row with no section heading above it; `ink` adds the block's top rule.
col_header <- function(sid, r, c1, c2, num = integer(0), ink = FALSE)
  c(fmt_section(sid, r, c1, c2, numeric_cols = num, heading = FALSE),
    if (ink) list(fmt_borders(sid, r, r, c1, c2, top = BORDER_INK)))

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


# Chart titles state what the 12 sample months show. A chart title cannot be a formula, so the ones on
# picker-driven charts stay descriptive, and the rest are computed here from the same rows the sheet gets.
usd <- function(x) paste0("$", formatC(round(x), format = "d", big.mark = ","))
of12 <- function(n) if (n == N_MONTHS) "every month" else sprintf("in %d of %d months", n, N_MONTHS)
nw_val <- with(nw, Checking + Savings + Investments + Retirement - CreditCard - CarLoan - StudentLoan)
d_nw <- nw_val[N_MONTHS] - nw_val[1]
top_cat <- sapply(mk, function(k) { e <- txn[mkey == k & txn$Type == "Expense", ]; names(which.max(tapply(e$Amount, e$Category, sum))) })
assets_end <- unlist(nw[N_MONTHS, c("Checking", "Savings", "Investments", "Retirement")])
debt <- with(nw, CreditCard + CarLoan + StudentLoan); assets <- with(nw, Checking + Savings + Investments + Retirement)
peak <- which.max(exp_m)
TTL <- list(
  ring   = if (all(top_cat == "Housing")) "Housing is the biggest share of spending" else "Spending by category, top 4 and the rest",
  flow   = sprintf("Spending peaked in %s at %s; income beat it %s", format(months[peak], "%B"), usd(exp_m[peak]), of12(sum(net_m > 0))),
  nw     = sprintf("Net worth %s %s since %s", if (d_nw >= 0) "grew" else "fell", usd(abs(d_nw)), format(months[1], "%B %Y")),
  sav    = sprintf("Saved money %s: income beat spending", of12(sum(net_m > 0))),
  lines  = sprintf("Debt fell %s while assets grew %s", usd(debt[1] - debt[N_MONTHS]), usd(assets[N_MONTHS] - assets[1])),
  assets = sprintf("%s holds %d%% of all assets", names(which.max(assets_end)), round(100 * max(assets_end) / sum(assets_end))))

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

# Theme first (font, chart series and ring slices follow it), then the named ranges, so formulas written below resolve on the first pass.
txn_name <- function(nm, col) fmt_named_range(S_TXN, nm, 5L, LAST_ROW, col, col)
batch_format(ss, list(
  do.call(fmt_theme_colors, THEME_DEFAULT),
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
CTRL <- c(2L, 11L); CTRL_A1 <- "Dashboard!$K$2"   # the month picker (Dashboard K2); Lists!L5 reads it

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
write_cell(ss, T_LST, 5, 12, gsub("PICK", CTRL_A1, '=IFERROR(IF(COUNTIF($B$5:$B$16,DATE(YEAR(PICK),MONTH(PICK),1))=0,MAX($B$5:$B$16),DATE(YEAR(PICK),MONTH(PICK),1)),MAX($B$5:$B$16))', fixed = TRUE))
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

# -- Budget (rows 6-14 categories, 15 total, 18-21 income, savings and settings, 23-42 chart data, 44-50 checks) --
write_cell(ss, T_BUD, 2, 2, "Budget vs actual")
write_cell(ss, T_BUD, 3, 2, '="In "&month_label&" you spent "&TEXT($D$15,"$#,##0")&" of a "&TEXT($C$15,"$#,##0")&" budget ("&IFERROR(TEXT($G$15,"0%"),$G$15)&")."')
write_cell(ss, T_BUD, 4, 2, "Pick the month on the Dashboard. Blue cells are inputs. Variance = budget minus actual, so a negative variance (red) is over budget.")
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
  # 1.2 is only the bar's display cap (120% of the track); 1 (= 100%) is what "over budget" means; "no budget" draws a full red bar.
  # Two values on one grey track: the used share in the accent (red when over), then the rest of the track.
  u <- sprintf("MIN(IF(ISNUMBER(G%d),G%d,1.2),1.2)", r, r)
  bar <- f_sparkline(sprintf("{%s,1.2-%s}", u, u), list(charttype = "bar", max = 1.2, color2 = hx(COL_SEP_SUBTLE),
           color1 = I(sprintf('IF(%s>1,"%s","%s")', u, hx(COL_NEGATIVE), hx(COL_ACCENT)))))
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
write_cell(ss, T_BUD, 21, 4, "A category turns amber at this share of its budget (red above 100%). Drives the status, the bars and the Dashboard.")
write_cell(ss, T_BUD, 23, 2, "Chart data: the four biggest categories this month and the rest (Dashboard ring and table)")
write_cell(ss, T_BUD, 24, 2, "Category"); write_cell(ss, T_BUD, 24, 3, "Spent")
for (k in 1:4) {
  write_cell(ss, T_BUD, 24L + k, 2, sprintf("=INDEX(SORT({$B$6:$B$14,$D$6:$D$14},2,FALSE),%d,1)", k))
  write_cell(ss, T_BUD, 24L + k, 3, sprintf("=INDEX(SORT({$B$6:$B$14,$D$6:$D$14},2,FALSE),%d,2)", k))
}
# at most five ring slices; whole dollars that add up: the rounded total minus the rounded top 4 (the Dashboard table shows this same cell)
write_cell(ss, T_BUD, 29, 2, "Everything else"); write_cell(ss, T_BUD, 29, 3, "=ROUND(D15,0)-SUMPRODUCT(ROUND(C25:C28,0))")
# chart data 2: share of budget used, biggest first (feeds the Dashboard budget table and chart); blanks count as 0, "no budget" as 200% (the axis top).
# Within / Over split the bars into two stacked series, so the over-budget bars turn red for whichever month is picked.
write_cell(ss, T_BUD, 32, 2, "Chart data: share of each budget used, biggest first (Dashboard budget table and chart)")
for (j in 1:4) write_cell(ss, T_BUD, 33, 1L + j, c("Category", "% of budget used", "Within budget", "Over budget")[j])
for (k in 1:9) {
  r <- 33L + k
  srt <- '{$B$6:$B$14,ARRAYFORMULA(IF(ISNUMBER($G$6:$G$14),$G$6:$G$14,IF($G$6:$G$14="",0,2)))}'
  write_cell(ss, T_BUD, r, 2, sprintf("=INDEX(SORT(%s,2,FALSE),%d,1)", srt, k))
  write_cell(ss, T_BUD, r, 3, sprintf("=INDEX(SORT(%s,2,FALSE),%d,2)", srt, k))
  write_cell(ss, T_BUD, r, 4, sprintf('=IF(C%d<=1,C%d,"")', r, r)); write_cell(ss, T_BUD, r, 5, sprintf('=IF(C%d>1,C%d,"")', r, r))
}
# self-checks: raw-data tests, so display rounding cannot trip them. Pivot total = largest number on its Grand Total row.
write_cell(ss, T_BUD, 44, 2, "Self-checks (live): every line should read OK")
write_cell(ss, T_BUD, 45, 2, "Check"); write_cell(ss, T_BUD, 45, 6, "Result"); write_cell(ss, T_BUD, 45, 7, "Status")
chk <- list(
  list("This month's Expense rows all sit in a budgeted category (difference, $)",
       '=ROUND(SUMIFS(txn_amt,txn_type,"Expense",txn_month,month_start)-SUM($D$6:$D$14),2)'),
  list("Pivot table total equals Trends 12-month spending (difference, $)",
       '=ROUND(IFERROR(MAX(INDEX(Trends!$B$24:$Q$40,MATCH("Grand Total",Trends!$B$24:$B$40,0),0)),0)-Trends!$D$18,2)'),
  list("Rows dated outside the 12 months (count; move the window on Lists)",
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
write_cell(ss, T_NW, 3, 2, '=LET(v,SUMIFS($L$6:$L$17,$B$6:$B$17,month_start),"Net worth is "&TEXT(v,"$#,##0")&" at the end of "&month_label&", "&TEXT(v-$L$6,"+$#,##0;-$#,##0")&" since the end of "&TEXT($B$6,"mmmm yyyy")&".")')
write_cell(ss, T_NW, 20, 2, "Month-end balances (sample data). Blue cells are inputs: type your own balances and the totals, changes and charts follow. Investments and retirement also grow with market gains and employer contributions that Transactions does not show.")
write_cell(ss, T_NW, 4, 3, "Assets"); write_cell(ss, T_NW, 4, 8, "Liabilities"); write_cell(ss, T_NW, 4, 12, "Net worth")
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
  else { write_cell(ss, T_NW, r, 13, "-"); write_cell(ss, T_NW, r, 14, "-") }
  # chart axis label, text so every month is labelled: the month's initial, because on the 432 px Dashboard chart
  # even "Oct" labels turn diagonal (checked live); the Month column carries the year. Picked month gets a dot.
  write_cell(ss, T_NW, r, 15, sprintf('=LEFT(TEXT($B%d,"mmm"),1)&IF($B%d=month_start," ●","")', r, r))
}

# -- Trends (rows 6-17 months, 18 total, 19 average; pivot from row 24) --
write_cell(ss, T_TRD, 2, 2, "Trends")
write_cell(ss, T_TRD, 3, 2, '="Over 12 months income was "&TEXT($C$18,"$#,##0")&" and spending "&TEXT($D$18,"$#,##0")&", so "&TEXT($F$18,"0%")&" of income was saved."')
write_cell(ss, T_TRD, 4, 2, "Every figure here is a formula or a pivot table over Transactions, so this tab has no inputs.")
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

# -- Dashboard. Grid: A16 | B224 | C-F 4x112 | G24 | H-J 3x96 | K144 | L16 (K holds the picker and the badge) --
# rows: 2-4 title, finding, meta | 6-9 KPI strip + note | 11-24 budget table + chart | 26-35 spending breakdown + ring |
#       37-52 twelve-month charts | 54-61 about
write_cell(ss, T_DASH, 2, 2, '="Personal finance, "&month_label')
write_cell(ss, T_DASH, 2, CTRL[2] - 1L, "Month")
write_cell(ss, T_DASH, CTRL[1], CTRL[2], as.character(months[SELECTED]))
# the finding: one live sentence about the picked month (over-budget names listed when there are 3 or fewer)
is_over  <- sprintf('(Budget!$G$6:$G$14="%s")+ISNUMBER(Budget!$G$6:$G$14)*(Budget!$G$6:$G$14>1)', NO_BUD)   # over 100%, or spending with no budget
over_n   <- paste0('SUMPRODUCT(', is_over, ')')
over_who <- paste0('REGEXREPLACE(IFERROR(TEXTJOIN(", ",TRUE,FILTER(Budget!$B$6:$B$14,', is_over, ')),""),", ([^,]*)$"," and $1")')
write_cell(ss, T_DASH, 3, 2, paste0('=LET(n,', over_n, ',who,', over_who, ',r,Budget!$D$20,g,Budget!$C$20,',
  'IF(n=0,"Every category stayed within budget",IF(n>3,n&" of 9 categories ran over budget",who&" ran over budget"))',
  '&"; the savings rate of "&TEXT(r,"0%")&IF(r>=g,IF(n>0," still beats"," beats")," misses")&" the "&TEXT(g,"0%")&" goal.")'))
write_cell(ss, T_DASH, 4, 2, sprintf('="Sample data · "&COUNTA(txn_amt)&" transactions · USD · built %s · View only? File > Make a copy to use the month picker"', Sys.Date()))
write_cell(ss, T_DASH, 4, CTRL[2], '=IF(Budget!$G$50="All pass","✓ Self-checks pass","✕ See Budget checks")')
# KPI strip: label / value / change, B (lead) to F
prior <- function(rng, tab = "Trends", key = "$B$6:$B$17") sprintf("SUMIFS(%s!%s,%s!%s,prev_start)", tab, rng, tab, key)
first <- 'COUNTIF(Trends!$B$6:$B$17,prev_start)=0'
K_COLS <- c(2:6, 8L)   # G is the gutter; the sixth KPI fills H-K under the picker
k_lab <- c('="Spent in "&month_label', "Income", "Saved", "Savings rate", "Net worth", "Over budget")
k_val <- c("=Budget!$D$15", "=Budget!$D$18", "=C7-B7", "=IFERROR(D7/C7,0)",
           "=SUMIFS('Net Worth'!$L$6:$L$17,'Net Worth'!$B$6:$B$17,month_start)",
           paste0('=', over_n, '&" of "&COUNTA(Budget!$B$6:$B$14)'))
k_chg <- c('=IFERROR(TEXT(B7/Budget!$C$15,"0%")&" of the "&TEXT(Budget!$C$15,"$#,##0")&" budget","no budget set")',
           paste0('=IF(', first, ',"no prior month",LET(p,', prior("$C$6:$C$17"), ',IF(p=0,"-",C7/p-1)))'),
           paste0('=IF(', first, ',"no prior month",D7-', prior("$E$6:$E$17"), ')'),
           paste0('=IF(', first, ',"no prior month",(E7-', prior("$F$6:$F$17"), ')*100)'),
           paste0("=IF(COUNTIF('Net Worth'!$B$6:$B$17,prev_start)=0,\"no prior month\",F7-", prior("$L$6:$L$17", "'Net Worth'"), ")"),
           paste0('=LET(n,', over_n, ',w,', over_who, ',IF(n=0,"None",IF(n>3,n&" categories",w)))'))   # names, like the finding
for (k in 1:6) { kc <- K_COLS[k]; write_cell(ss, T_DASH, 6, kc, k_lab[k]); write_cell(ss, T_DASH, 7, kc, k_val[k]); write_cell(ss, T_DASH, 8, kc, k_chg[k]) }
write_cell(ss, T_DASH, 9, 2, paste0('=IF(', first, ',"The first month in the sample has nothing to compare with.","Changes are vs "&TEXT(prev_start,"mmmm yyyy")&": green is better, red is worse.")'))
# Budget by category, sorted by share used (Budget!B34:B42), with the budget chart beside it
write_cell(ss, T_DASH, 11, 2, "Budget by category")
write_cell(ss, T_DASH, 11, 6, paste0('=', over_n, '&" of 9 over budget"'))
for (j in 1:5) write_cell(ss, T_DASH, 12, 1L + j, c("Category", "Budget", "Spent", "Used", "Status")[j])
for (k in 1:9) {
  r <- 12L + k; look <- function(col) sprintf("=INDEX(Budget!$%s$6:$%s$14,MATCH($B%d,Budget!$B$6:$B$14,0))", col, col, r)
  write_cell(ss, T_DASH, r, 2, sprintf("=Budget!$B$%d", 33L + k))
  for (j in 1:4) write_cell(ss, T_DASH, r, 2L + j, look(c("C", "D", "G", "I")[j]))
}
write_cell(ss, T_DASH, 22, 2, "Total"); write_cell(ss, T_DASH, 22, 3, "=Budget!$C$15")
write_cell(ss, T_DASH, 22, 4, "=Budget!$D$15"); write_cell(ss, T_DASH, 22, 5, "=Budget!$G$15")
write_cell(ss, T_DASH, 24, 2, '="Status: amber from "&TEXT(warn_at,"0%")&" of a budget, red over 100% or spending with no budget. Budgets and the threshold are set on the Budget tab."')
# Where the money went: the ring's legend as a table (each bar is its slice's colour), whole dollars that add up
write_cell(ss, T_DASH, 26, 2, '="Where the money went in "&month_label')
for (j in 1:3) write_cell(ss, T_DASH, 27, 1L + j, c("Category", "Spent", "Share")[j])
for (k in 1:5) {
  r <- 27L + k
  write_cell(ss, T_DASH, r, 2, sprintf("=Budget!$B$%d", 24L + k))
  write_cell(ss, T_DASH, r, 3, if (k <= 4) sprintf("=ROUND(Budget!$C$%d,0)", 24L + k) else "=Budget!$C$29")
  write_cell(ss, T_DASH, r, 4, sprintf("=IFERROR(C%d/$C$33,0)", r))
  bar <- f_sparkline(sprintf("D%d", r), list(charttype = "bar", max = I("MAX($D$28:$D$32)"), color1 = paste0("#", CHART_PALETTE[k])))
  write_cell(ss, T_DASH, r, 5, sprintf('=IF(MAX($D$28:$D$32)=0,"",%s)', fraw(bar)))
}
write_cell(ss, T_DASH, 33, 2, "Total spending"); write_cell(ss, T_DASH, 33, 3, "=SUM(C28:C32)"); write_cell(ss, T_DASH, 33, 4, "=SUM(D28:D32)")
write_cell(ss, T_DASH, 35, 2, "The four biggest categories this month and everything else, in whole dollars that add up to the total.")
write_cell(ss, T_DASH, 37, 2, "Twelve months")
write_cell(ss, T_DASH, 37, 11, "● marks the picked month")
write_cell(ss, T_DASH, 54, 2, "About this sample")
about <- c("Sample data: all numbers are synthetic. No real people, merchants or accounts.",
           "Built with the r-googlesheets4 skill (github.com/salvadoraveldano/r-googlesheets4)",
           "Built on googlesheets4 by Jennifer Bryan and Posit (googlesheets4.tidyverse.org)",
           "How to use: pick a month at the top right, then edit the blue cells on any tab.",
           "Input", "Formula", "The month picker updates the KPIs, the budget table and chart, and the spending breakdown. The 12-month charts show every month.")
for (k in seq_along(about)) write_cell(ss, T_DASH, 54L + k, 2, about[k])
write_cell(ss, T_DASH, 59, 3, "Blue text on pale blue: a value you can change.")
write_cell(ss, T_DASH, 60, 3, "Black text: a formula. Editing it shows a warning.")

flush_writes(ss, strict = TRUE)

# =============================================================================
# Formatting, one batch per tab (strict: stops on any HTTP error)
# =============================================================================
# fmt_tab_base() lays the body style, gutters, widths and the title/finding/meta rows (2-4); later requests in the
# same batch win, so the tables below reset rows 4-5 where a tab's header sits there.

# ---- Lists ----
b <- new_batch()
b$push(fmt_tab_base(S_LST, 40, 13, "model", widths = c(140, 24, 130, 80, 24, 120, 24, 90, 24, 130, 160), inputs = TRUE, freeze_rows = 4))
for (g in list(c(16, 2, 2), c(16, 4, 5), c(7, 7, 7), c(6, 9, 9), c(7, 11, 12))) {
  b$push(col_header(S_LST, 4, g[2], g[3], ink = TRUE)); b$push(fmt_table_body(S_LST, 5, g[1], g[2], g[3]))
}
b$push(fmt_cells(S_LST, 5, 16, 2, 2, numfmt = NF_MONTH_LONG, halign = "LEFT"))
b$push(apply_style(S_LST, 5, 5, 2, 2, STYLE_INPUT))                       # first month: the one input
b$push(fmt_cells(S_LST, 5, 7, 11, 11, font_color = COL_TEXT_3))
b$push(fmt_cells(S_LST, 5, 6, 12, 12, numfmt = NF_DAY, halign = "LEFT")); b$push(fmt_cells(S_LST, 7, 7, 12, 12, halign = "LEFT"))
b$push(apply_style(S_LST, 9, 9, 11, 11, STYLE_NOTE))
batch_format(ss, b$get(), strict = TRUE)

# ---- Transactions ----
BAND_LAST <- 4L + nrow(txn) + 50L       # the input fill covers the used rows plus a margin: to LAST_ROW it prints ~20 blank blue pages
b <- new_batch()
b$push(fmt_tab_base(S_TXN, LAST_ROW, 9, "model", widths = c(110, 200, 120, 110, 100, 90, 100), inputs = TRUE, freeze_rows = 4))
b$push(fmt_gridlines(S_TXN, show = TRUE))
b$push(col_header(S_TXN, 4, 2, 8, num = 6, ink = TRUE))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 2, 2, numfmt = NF_DAY, halign = "LEFT"))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 6, 6, numfmt = NF_USD2, halign = "RIGHT"))
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 8, 8, numfmt = NF_MONTH, halign = "LEFT", font_color = COL_TEXT_3))
b$push(fmt_cells(S_TXN, 4, LAST_ROW, 7, 7, halign = "CENTER"))            # Type, clear of the right-aligned Amount
b$push(fmt_cells(S_TXN, 5, LAST_ROW, 2, 7, font_color = COL_INPUT_FG))      # typed-in columns: blue, also on rows you add
b$push(apply_style(S_TXN, 5, BAND_LAST, 2, 7, STYLE_INPUT))
b$push(fmt_borders(S_TXN, 5, BAND_LAST, 2, 7, inner_h = list(style = "SOLID", color = COL_WHITE)))   # rows stay readable on the fill
batch_format(ss, b$get(), strict = TRUE)

# ---- Budget ----
b <- new_batch()
b$push(fmt_tab_base(S_BUD, 55, 10, "model", widths = c(170, 110, 110, 110, 100, 80, 190, 120), inputs = TRUE,
                    freeze_rows = 0))   # no freeze: frozen rows repeat on every printed page, over unrelated blocks
b$push(col_header(S_BUD, 5, 2, 9, num = 3:7, ink = TRUE)); b$push(fmt_cells(S_BUD, 5, 5, 8, 9, halign = "CENTER"))
b$push(fmt_table_body(S_BUD, 6, 15, 2, 9, numeric_cols = 3:7, numfmt = list(NF_USD, NF_USD2, NF_USD2C, NF_PCT1, NF_PCT1), total_rows = 15))   # actual: a real zero prints $0.00
b$push(apply_style(S_BUD, 6, 14, 3, 3, STYLE_INPUT))
b$push(fmt_status(S_BUD, 6, 15, 9, 9, c("Over budget" = "negative", "No budget" = "negative", "Close to limit" = "warning")))
b$push(col_header(S_BUD, 17, 2, 6, num = 3:6, ink = TRUE))
b$push(fmt_table_body(S_BUD, 18, 21, 2, 6, numeric_cols = 3:6, numfmt = list(NF_USD, NF_USD2C, NF_USD2C, NF_PCT1)))
b$push(fmt_cells(S_BUD, 20, 20, 3, 4, numfmt = NF_PCT1)); b$push(fmt_cells(S_BUD, 20, 20, 5, 5, numfmt = NF_PTS))
b$push(fmt_cells(S_BUD, 21, 21, 3, 3, numfmt = NF_PCT0)); b$push(apply_style(S_BUD, 21, 21, 4, 4, STYLE_NOTE))
for (r in c(18, 20, 21)) b$push(apply_style(S_BUD, r, r, 3, 3, STYLE_INPUT))   # expected income, savings goal, warning threshold
for (s in list(c(23, 24, 3, 25, 29), c(32, 33, 5, 34, 42), c(44, 45, 7, 46, 50))) {   # heading, header, last col, body
  b$push(fmt_section(S_BUD, s[1], 2, 9, header = FALSE)); b$push(col_header(S_BUD, s[2], 2, s[3], num = 3:s[3]))
}
b$push(fmt_table_body(S_BUD, 25, 29, 2, 3, numeric_cols = 3, numfmt = NF_USD))
b$push(fmt_table_body(S_BUD, 34, 42, 2, 5, numeric_cols = 3:5, numfmt = NF_PCT0))
b$push(fmt_table_body(S_BUD, 46, 50, 2, 7, numeric_cols = 6, numfmt = NF_USD2, total_rows = 50))
b$push(fmt_cells(S_BUD, 45, 45, 2, 5, halign = "LEFT")); b$push(fmt_cells(S_BUD, 45, 45, 7, 7, halign = "CENTER"))
b$push(fmt_cells(S_BUD, 48, 50, 6, 6, numfmt = NF_INT))
b$push(fmt_status(S_BUD, 46, 50, 7, 7, c(Check = "negative", Review = "negative")))   # OK and All pass stay plain
# chart-data rows at the default 21 px, so the first printed page ends after the first chart-data block
for (rh in list(c(16, 16, 12), c(22, 22, 12), c(25, 29, 21), c(31, 31, 20), c(34, 42, 21), c(43, 43, 20))) b$push(fmt_row_height(S_BUD, rh[1], rh[2], rh[3]))
batch_format(ss, b$get(), strict = TRUE)

# ---- Net Worth ----
b <- new_batch()
b$push(fmt_tab_base(S_NW, 45, 16, "model", widths = c(96, 98, 98, 104, 104, 108, 96, 90, 96, 112, 112, 112, 84, 96), inputs = TRUE, freeze_rows = 5))
b$push(apply_style(S_NW, 4, 4, 2, 15, STYLE_HEADER, font_size = 10, font_color = COL_INK, wrap = FALSE))   # group labels
b$push(fmt_borders(S_NW, 4, 4, 2, 15, top = BORDER_INK)); b$push(fmt_row_height(S_NW, 4, 4, 24L))
b$push(col_header(S_NW, 5, 2, 15, num = 3:14)); b$push(fmt_row_height(S_NW, 5, 5, 36L))
b$push(fmt_table_body(S_NW, 6, 17, 2, 15, numeric_cols = 3:14, total_col = c(7, 11, 12),
                      numfmt = c(rep(list(NF_USD_NEG), 10), list(NUMFMT_DELTA_CURRENCY, NUMFMT_DELTA_PCT))))   # chart sources: $0, not "-"
b$push(fmt_cells(S_NW, 6, 17, 2, 2, numfmt = NF_MONTH, halign = "LEFT"))
b$push(fmt_cells(S_NW, 6, 6, 13, 14, font_color = COL_TEXT_3))
b$push(apply_style(S_NW, 6, 17, 15, 15, STYLE_NOTE, halign = "CENTER")); b$push(fmt_cells(S_NW, 5, 5, 15, 15, halign = "CENTER"))
for (g in list(c(3, 6), c(8, 10))) b$push(apply_style(S_NW, 6, 17, g[1], g[2], STYLE_INPUT))
b$push(apply_style(S_NW, 20, 20, 2, 2, STYLE_NOTE)); b$push(fmt_row_height(S_NW, 18, 19, 12L))
batch_format(ss, b$get(), strict = TRUE)

# ---- Trends ----
b <- new_batch()
b$push(fmt_tab_base(S_TRD, 45, 16, "model", widths = c(128, rep(80, 12), 104), freeze_rows = 3))   # C..N months, O = Grand Total
b$push(col_header(S_TRD, 5, 2, 7, num = 3:6, ink = TRUE))
b$push(fmt_table_body(S_TRD, 6, 19, 2, 7, numeric_cols = 3:6, numfmt = c(rep(list(NF_USD_NEG), 3), list(NF_PCT1)), total_rows = 18))
b$push(fmt_cells(S_TRD, 6, 17, 2, 2, numfmt = NF_MONTH, halign = "LEFT"))
b$push(apply_style(S_TRD, 6, 17, 7, 7, STYLE_NOTE, halign = "CENTER")); b$push(fmt_cells(S_TRD, 5, 5, 7, 7, halign = "CENTER"))
b$push(fmt_row_height(S_TRD, 20, 21, 10L))
b$push(fmt_section(S_TRD, 22, 2, 15, header = FALSE)); b$push(apply_style(S_TRD, 23, 23, 2, 2, STYLE_NOTE)); b$push(fmt_row_height(S_TRD, 23, 23, 22L))
batch_format(ss, b$get(), strict = TRUE)

# ---- Dashboard ----
BOX <- list(style = "SOLID_MEDIUM", color = COL_ACCENT)
b <- new_batch(); sd <- S_DASH
b$push(fmt_tab_base(sd, 62, 12, "dashboard", widths = c(224, rep(112, 4), 24, rep(96, 3), 144)))
b$push(apply_style(sd, 2, 2, CTRL[2] - 1L, CTRL[2] - 1L, STYLE_NOTE, halign = "RIGHT"))      # "Month"
b$push(apply_style(sd, CTRL[1], CTRL[1], CTRL[2], CTRL[2], STYLE_CONTROL, valign = "MIDDLE", numfmt = NF_MONTH_LONG))
b$push(fmt_borders(sd, CTRL[1], CTRL[1], CTRL[2], CTRL[2], top = BOX, bottom = BOX, left = BOX, right = BOX))
b$push(fmt_status(sd, 4, 4, CTRL[2], CTRL[2], c("✓" = "positive", "✕" = "negative"), op = "starts_with"))   # self-check badge
b$push(fmt_kpi_strip(sd, 6, K_COLS, lead = 2, good = c("down", "up", "up", "up", "up", "none"), rule_end_col = 11,
                     value_numfmt = list(NF_USD_NEG, NF_USD_NEG, NF_USD_NEG, NF_PCT1, NF_USD_NEG, NULL),
                     delta_numfmt = list(NULL, NUMFMT_DELTA_PCT, NUMFMT_DELTA_CURRENCY, NUMFMT_DELTA_PT, NUMFMT_DELTA_CURRENCY, NULL),
                     tol = c(0, 0.0005, 0.5, 0.05, 0.5, 0)))   # half the last shown digit: "+0.0 pts" stays grey
b$push(apply_style(sd, 9, 9, 2, 2, STYLE_NOTE))
for (s in c(11, 26, 37, 54)) b$push(fmt_section(sd, s, 2, 11, header = FALSE, meta_col = if (s == 11) 6 else if (s == 37) 11 else NULL))
b$push(col_header(sd, 12, 2, 6, num = 3:5)); b$push(fmt_cells(sd, 12, 12, 6, 6, halign = "CENTER"))
b$push(fmt_table_body(sd, 13, 22, 2, 6, numeric_cols = 3:5, numfmt = list(NF_USD, NF_USD2, NF_PCT0), density = "dashboard", total_rows = 22))   # spent in cents: the column adds up
b$push(fmt_status(sd, 13, 21, 6, 6, c("Over budget" = "negative", "No budget" = "negative", "Close to limit" = "warning")))
b$push(col_header(sd, 27, 2, 5, num = 3:4))
b$push(fmt_table_body(sd, 28, 33, 2, 5, numeric_cols = 3:4, numfmt = list(NF_USD, NF_PCT0), density = "dashboard", total_rows = 33))
for (r in c(24, 35)) b$push(apply_style(sd, r, r, 2, 2, STYLE_NOTE))
b$push(apply_style(sd, 55, 61, 2, 3, STYLE_BODY, font_color = COL_TEXT_2))
b$push(fmt_cells(sd, 56, 57, 2, 2, font_color = COL_ACCENT_700))             # the two link rows (theme link colour)
b$push(apply_style(sd, 59, 59, 2, 2, STYLE_INPUT)); b$push(fmt_cells(sd, 60, 60, 2, 2, font_color = COL_INK))   # colour key
for (rh in list(c(5, 5, 12), c(9, 10, 20), c(23, 23, 8), c(24, 25, 20), c(34, 34, 8), c(35, 36, 20), c(53, 53, 20), c(55, 61, 22)))
  b$push(fmt_row_height(sd, rh[1], rh[2], rh[3]))
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# Conditional formatting: colour only where there is risk (own batch per tab so one bad rule cannot sink the rest)
# =============================================================================
b <- new_batch()
for (rg in list(c(6, 15, 5, 6), c(18, 19, 5, 6), c(20, 20, 5, 5)))
  b$cf(fmt_cond_number, S_BUD, rg[1], rg[2], rg[3], rg[4], 0, "less", font_color = COL_NEGATIVE)
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()   # selected month: raised grey and bold, never blue (blue means "you can type here")
b$cf(fmt_cond_formula, S_NW, 6, 17, 2, 15, '=RIGHT($O6,1)="●"', bg_color = COL_RAISED, bold = TRUE)
b$cf(fmt_cond_number, S_NW, 7, 17, 13, 14, 0, "less", font_color = COL_NEGATIVE)
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()
b$cf(fmt_cond_formula, S_TRD, 6, 17, 2, 7, '=RIGHT($G6,1)="●"', bg_color = COL_RAISED, bold = TRUE)
b$cf(fmt_cond_number, S_TRD, 6, 17, 5, 5, 0, "less", font_color = COL_NEGATIVE)
batch_format(ss, b$get(), strict = TRUE)

b <- new_batch()   # Type must match the category's kind (Lists)
b$cf(fmt_cond_formula, S_TXN, 5, LAST_ROW, 7, 7, '=AND($D5<>"",$G5<>"",$G5<>IFERROR(VLOOKUP($D5,INDIRECT("Lists!$D$5:$E$16"),2,FALSE),$G5))',
     font_color = STATUS$negative$ink, bg_color = STATUS$negative$fill, bold = TRUE)
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# Dropdowns and filter
# =============================================================================
batch_format(ss, list(
  fmt_dropdown_range(S_DASH, CTRL[1], CTRL[1], CTRL[2], CTRL[2], "=Lists!$B$5:$B$16"),
  fmt_validation(S_LST, 5, 5, 2, 2, "CUSTOM_FORMULA", "=AND(ISNUMBER(B5),DAY(B5)=1)",
                 input_message = "Type the first day of the first month, for example 2025-10-01. The other eleven months follow."),
  fmt_validation(S_BUD, 6, 14, 3, 3, "NUMBER_GREATER_THAN_EQ", 0,
                 input_message = "Enter a monthly budget of 0 or more. A category with a 0 budget shows as 'no budget' when you spend in it.")),
  strict = TRUE)
batch_format(ss, list(
  fmt_dropdown_range(S_TXN, 5, LAST_ROW, 4, 4, "=Lists!$D$5:$D$16"),
  fmt_dropdown_range(S_TXN, 5, LAST_ROW, 5, 5, "=Lists!$G$5:$G$7"),
  fmt_dropdown_range(S_TXN, 5, LAST_ROW, 7, 7, "=Lists!$I$5:$I$6"),
  fmt_validation(S_TXN, 5, LAST_ROW, 6, 6, "NUMBER_GREATER", 0,
                 input_message = "Enter a positive amount. The Type column says whether it is income or an expense."),
  fmt_validation(S_TXN, 5, LAST_ROW, 2, 2, "DATE_IS_VALID", input_message = "Enter a date, for example 2026-03-14."),
  fmt_basic_filter(S_TXN, 4, LAST_ROW, 2, 7)),   # B:G; column H is one array formula, sorting must not touch it
  strict = TRUE)

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
# Charts (cross-tab sources; chart data sits in visible columns). One hue per chart: the accent on the main
# series, greys for comparisons, the negative mark only on the bars over budget.
# =============================================================================
LBL_TRD <- c(5, 17, 7, 7); LBL_NW <- c(5, 17, 15, 15)      # text month labels ("Jan 2026", "Sep ●"; Net Worth "J", "S ●"): every month shown, picked one marked
MONTH_AXIS <- "Month (● = picked month)"
batch_format(ss, list(
  # Horizontal bars keep the nine category names flat; a BAR chart cannot draw the dashed 100% line, so the axis says it.
  fmt_chart_bar(S_BUD, "Share of each budget used, biggest first", domain_range = c(33, 42, 2, 2),
                stacked_type = "STACKED", legend = "TOP_LEGEND",
                series_list = list(list(range = c(33, 42, 4, 4), color = COL_ACCENT),
                                   list(range = c(33, 42, 5, 5), color = COL_NEGATIVE)),
                anchor = c(12L, 8L), size = c(432L, 334L), anchor_sheet_id = S_DASH,
                x_title = "% of monthly budget (past 100% is over budget)", style = STYLE_CHART),
  fmt_chart_pie(S_BUD, TTL$ring, domain_range = c(25, 29, 2, 2), data_range = c(25, 29, 3, 3), donut = TRUE,
                legend = "NO_LEGEND", anchor = c(27L, 8L), size = c(432L, 222L), anchor_sheet_id = S_DASH, style = STYLE_CHART),
  fmt_chart_basic(S_TRD, TTL$flow, "COLUMN", domain_range = LBL_TRD, legend = "TOP_LEGEND",   # left axis only: the KPI and Trends carry the rate
                  series_list = list(list(range = c(5, 17, 3, 3), color = GREY),
                                     list(range = c(5, 17, 4, 4), color = COL_ACCENT)),
                  anchor = c(38L, 2L), size = c(672L, 300L), anchor_sheet_id = S_DASH,
                  x_title = MONTH_AXIS, y_title = "USD per month", style = STYLE_CHART),
  # LINE, not AREA: an area chart puts its last point on the plot edge and Sheets then drops that label at this width.
  fmt_chart_basic(S_NW, TTL$nw, "LINE", domain_range = LBL_NW,
                  series_list = list(list(range = c(5, 17, 12, 12), color = COL_ACCENT, line = list(width = 3))),
                  anchor = c(38L, 8L), size = c(432L, 300L), anchor_sheet_id = S_DASH, legend = "NO_LEGEND",
                  x_title = MONTH_AXIS, y_title = "USD", style = STYLE_CHART),
  fmt_chart_basic(S_TRD, TTL$sav, "COLUMN", domain_range = LBL_TRD,
                  series_list = list(list(range = c(5, 17, 5, 5), color = COL_ACCENT)),
                  anchor = c(5L, 8L), size = c(640L, 356L), offset_x = 12L, legend = "NO_LEGEND",
                  x_title = MONTH_AXIS, y_title = "Savings (income minus spending), USD", style = STYLE_CHART),
  fmt_chart_basic(S_NW, TTL$lines, "LINE", domain_range = LBL_NW, legend = "TOP_LEGEND",
                  series_list = list(list(range = c(5, 17, 7, 7), color = GREY, line = list(width = 2)),
                                     list(range = c(5, 17, 11, 11), color = DARK, line = list(width = 2)),
                                     list(range = c(5, 17, 12, 12), color = COL_ACCENT, line = list(width = 3))),
                  anchor = c(22L, 2L), size = c(696L, 330L),
                  x_title = MONTH_AXIS, y_title = "USD", style = STYLE_CHART),
  fmt_chart_basic(S_NW, TTL$assets, "AREA", domain_range = LBL_NW, stacked_type = "STACKED", legend = "TOP_LEGEND",
                  series_list = lapply(3:6, function(cl) list(range = c(5, 17, cl, cl),
                                         color = list(DARK, GREY, COL_ACCENT_400, COL_ACCENT)[[cl - 2L]])),
                  anchor = c(22L, 9L), size = c(696L, 330L),
                  x_title = MONTH_AXIS, y_title = "USD", style = STYLE_CHART)),
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
PIV_HDR <- PIV_R + r_first - 2L; PIV_TOT <- PIV_R + r_last          # last header row, Grand Total row
b <- new_batch()
b$push(fmt_cells(S_TRD, PIV_R, PIV_TOT, 2, 17, bg_color = COL_WHITE))                         # drop the pivot's own grey header fills
b$push(apply_style(S_TRD, PIV_R, PIV_HDR, 2, 17, STYLE_HEADER, italic = FALSE, halign = "RIGHT"))   # italic = FALSE: Sheets italicises the pivot's own labels
b$push(fmt_cells(S_TRD, PIV_R, PIV_HDR, 2, 2, halign = "LEFT"))
b$push(fmt_borders(S_TRD, PIV_HDR, PIV_HDR, 2, 15, bottom = BORDER_STRONG))
b$push(fmt_table_body(S_TRD, PIV_HDR + 1L, PIV_TOT, 2, 15, numeric_cols = 3:15, numfmt = NF_USD_NEG, total_rows = PIV_TOT, total_col = 15))
b$push(fmt_cells(S_TRD, PIV_HDR + 1L, PIV_TOT, 2, 17, italic = FALSE, font_color = COL_INK))
b$push(fmt_row_height(S_TRD, PIV_HDR + 1L, PIV_TOT - 1L, 21L))     # so the Grand Total row prints on the first page
b$push(fmt_cells(S_TRD, PIV_HDR + 1L, PIV_TOT, 16, 17, numfmt = NF_USD_NEG, halign = "RIGHT"))   # an extra month column is formatted too
# One colour scale per category row, so each shows its own busy months (Travel in Dec, Jun, Mar). A single scale
# over all rows is washed out by the rent. Housing is a fixed cost, so it stays unshaded.
for (cat in setdiff(CAT_EXP, "Housing"))
  b$cf(fmt_cond_color_scale, S_TRD, PIV_R + match(cat, lab) - 1L, PIV_R + match(cat, lab) - 1L, 3L, 2L + N_MONTHS,
       min_color = SCALE_HEAT$min_color, mid_color = SCALE_HEAT$mid_color, max_color = SCALE_HEAT$max_color)
batch_format(ss, b$get(), strict = TRUE)

# =============================================================================
# Protection (warning-only: anyone can still edit after a prompt) and the two real links
# =============================================================================
batch_format(ss, list(
  fmt_protected_range(S_DASH, description = "Formulas and layout. Only the month picker is meant to be changed.",
                      unprotected_ranges = list(grid_range(S_DASH, CTRL[1], CTRL[1], CTRL[2], CTRL[2]))),
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

batch_format(ss, list(link_cells_req(S_DASH, 56L, 2L,
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
