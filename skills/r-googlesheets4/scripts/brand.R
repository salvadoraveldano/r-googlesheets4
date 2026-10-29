# =============================================================================
# brand.R — your accent colour and font (optional)
# =============================================================================
#
# The default look ("Ledger", references/design-principles.md) already loads
# with gs_helpers.R. Source this file only to change the accent or the font:
# edit the two values below and everything that follows the accent (chart
# series, the theme, the control box, colour scales, waterfall totals) moves
# with it. Inputs stay blue on purpose, so "blue = you can type here" holds.
#
#   source("scripts/gs_helpers.R")
#   source("scripts/gs_buffer.R")
#   source("scripts/brand.R")
#   batch_format(ss, list(do.call(fmt_theme_colors, THEME_DEFAULT)), strict = TRUE)
# =============================================================================

if (!exists("ds_tokens"))  stop("Source gs_helpers.R before brand.R")
if (!exists("STYLE_BODY")) stop("Source gs_buffer.R before brand.R")

# ── Edit these -----------------------------------------------------------------
ACCENT_HEX <- "2457C5"   # one brand colour, at least 3:1 on white (ds_tokens() checks)
BRAND_FONT <- "Roboto"   # renders in the grid, charts and PDF; "Arial" also works

list2env(ds_tokens(ACCENT_HEX, BRAND_FONT), environment())

# ── Old names, kept so existing scripts run ------------------------------------
STYLE_BRAND_TITLE              <- STYLE_TITLE
STYLE_BRAND_SECTION_HEADER     <- STYLE_SECTION_HEADER
STYLE_BRAND_SECTION_HEADER_ALT <- STYLE_SECTION_HEADER
STYLE_BRAND_SUBTOTAL           <- STYLE_SUBTOTAL
STYLE_BRAND_EXPENSE_ROW        <- list(font_color = COL_INK)   # the sign carries the meaning, not red
STYLE_BRAND_INPUT_LIVE         <- STYLE_INPUT
STYLE_BRAND_HIGHLIGHT_COL      <- list(bg_color = COL_RAISED, bold = TRUE, halign = "RIGHT")

# Negatives in the number format's own red. `[Red]` is one of the colours a
# format may name (Black, Blue, Cyan, Green, Magenta, Red, White, Yellow or
# [ColorN]); for an exact hex, colour the cells with fmt_cond_negative().
NUMFMT_CURRENCY_NEG <- list(type = "CURRENCY", pattern = "$#,##0;[Red]-$#,##0")

#' write_section_header() under its old brand name; `alt` is accepted and
#' ignored (there is one section style now).
write_section_header_brand <- function(ss, sheet_name, sheet_id, row, label,
                                       start_col = 3L, end_col = 8L,
                                       alt = FALSE, ...) {
  write_section_header(ss, sheet_name, sheet_id, row, label,
                       start_col = start_col, end_col = end_col, ...)
}
