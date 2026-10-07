# =============================================================================
# brand.R — customizable brand preset (opt-in)
# =============================================================================
#
# One editable block of colors/fonts plus style presets built on the generic
# defaults in gs_buffer.R. Change the palette below to match your organization;
# everything else follows.
#
# Source AFTER `gs_helpers.R` and `gs_buffer.R` — values here override the
# generic defaults.
#
#   source("scripts/gs_helpers.R")
#   source("scripts/gs_buffer.R")
#   source("scripts/brand.R")
#   apply_style(sid, ..., STYLE_BRAND_SECTION_HEADER)
# =============================================================================

if (!exists("hex_to_color")) stop("Source gs_helpers.R before brand.R")
if (!exists("STYLE_BODY"))   stop("Source gs_buffer.R before brand.R")

# ── Palette: edit these ------------------------------------------------------
BRAND_FONT <- "Arial"  # web-safe, portable to PDF export

COL_BRAND        <- hex_to_color("2457C5")  # primary: titles, section headers
COL_BRAND_DEEP   <- hex_to_color("163A85")  # second-level banner
COL_BRAND_SUBTLE <- hex_to_color("E9EFFB")  # subtotal / soft-fill background
COL_INK          <- hex_to_color("12161C")  # near-black text

# Semantic colors: reserve for data (variance, status), never decoration.
COL_POSITIVE      <- hex_to_color("18A957")
COL_NEGATIVE      <- hex_to_color("E5484D")
COL_WARNING       <- hex_to_color("F5A524")
COL_WARNING_SOFT  <- hex_to_color("FEF4E6")

# ── Style presets ------------------------------------------------------------
STYLE_BRAND_TITLE <- modifyList(STYLE_TITLE, list(
  font_family = BRAND_FONT, font_size = 26, bold = TRUE, font_color = COL_BRAND
))

STYLE_BRAND_SECTION_HEADER <- modifyList(STYLE_SECTION_HEADER, list(
  bg_color = COL_BRAND, font_color = COL_WHITE
))

STYLE_BRAND_SECTION_HEADER_ALT <- modifyList(STYLE_SECTION_HEADER, list(
  bg_color = COL_BRAND_DEEP, font_color = COL_WHITE
))

STYLE_BRAND_SUBTOTAL    <- list(bold = TRUE, bg_color = COL_BRAND_SUBTLE)
STYLE_BRAND_EXPENSE_ROW <- list(font_color = COL_NEGATIVE, bold = TRUE)
STYLE_BRAND_INPUT_LIVE  <- list(font_color = COL_BRAND, italic = TRUE)
STYLE_BRAND_HIGHLIGHT_COL <- list(
  bg_color = COL_WARNING_SOFT, bold = TRUE, halign = "RIGHT"
)

# ── Number format with red negatives ----------------------------------------
# Number formats can only color negatives with the legacy palette (`[Red]`,
# `[ColorN]`), not arbitrary hex. For an exact brand red, color the cells with
# `fmt_cond_negative(..., color = COL_NEGATIVE)` instead.
NUMFMT_CURRENCY_NEG <- list(type = "CURRENCY", pattern = "$#,##0;[Red]-$#,##0")

# ── Section-header convenience wrapper --------------------------------------
write_section_header_brand <- function(ss, sheet_name, sheet_id, row, label,
                                       start_col = 3L, end_col = 8L,
                                       alt = FALSE, ...) {
  bg <- if (isTRUE(alt)) COL_BRAND_DEEP else COL_BRAND
  write_section_header(ss, sheet_name, sheet_id, row, label,
                       start_col = start_col, end_col = end_col,
                       bg_color = bg, ...)
}
