# minimal.R — smallest end-to-end example
#
# Creates a sheet, writes a tibble, formats the header, verifies the result
# (sharing optional — uncomment at the bottom). Connects with the Google account
# saved by `bash scripts/gs_setup.sh auth <email>`.
#
# Run with: Rscript examples/minimal.R

USER_EMAIL <- NULL  # NULL = account saved by gs_setup.sh; or "you@example.com"

# Source the helpers
SKILL <- Sys.getenv("GS_SKILL_DIR", ".")  # the skill directory (default: run from it)
source(file.path(SKILL, "scripts/gs_helpers.R"))
source(file.path(SKILL, "scripts/gs_buffer.R"))
source(file.path(SKILL, "scripts/gs_qa.R"))      # post-build audits
source(file.path(SKILL, "scripts/gs_modern.R"))  # fmt_auto_resize_cols

# ── Connect ── uses the login saved by scripts/gs_setup.sh; never opens a browser
gs_connect(USER_EMAIL)

# Create a sheet with one tab and some data
ss <- gs_open_or_create("Quick Demo — minimal.R", "Summary")
sheet_write(head(mtcars), ss, sheet = "Summary")
sid <- get_sheet_id(ss, "Summary")

# Format: brand-blue bold header, frozen, gridlines off
batch_format(ss, list(
  fmt_freeze(sid, rows = 1L),
  fmt_gridlines(sid, show = FALSE),
  fmt_cells(sid, 1, 1, 1, ncol(mtcars),
            font_family = "Arial", bold = TRUE, font_size = 11,
            font_color = COL_WHITE, bg_color = hex_to_color("2457C5"),  # brand blue
            halign = "CENTER"),
  fmt_auto_resize_cols(sid, 1, ncol(mtcars))
))

# Verify — batch_format() doesn't throw on HTTP errors, so re-read the live
# state instead of trusting a self-reported success
audit_chart_sources(as.character(ss), sid)
stopifnot(first_visible_col(as.character(ss), sid) <= 1L)
cat("[QA] post-build checks passed\n")

# Optionally share — uncomment and edit the email
# drive_share(ss, role = "reader", type = "user",
#             emailAddress = "viewer@example.com")

cat("Sheet URL: ", as.character(ss), "\n", sep = "")
cat("View it: ", gs4_browse(ss), "\n", sep = "")
