# =============================================================================
# gs_visual_qa.R — Visual QA: layout audit + PDF export + page images
# =============================================================================
#
# Two layers, because each catches what the other misses:
#
#   1. audit_layout()  — deterministic checks on the on-screen grid, from one
#                        spreadsheets.get: truncated text, "###" numbers, narrow
#                        or wide columns, short rows, hidden content, merges
#                        over thin columns, mixed alignment, low contrast.
#   2. visual_qa()     — runs the audit, exports each tab to PDF, and turns the
#                        pages into PNGs so the agent can LOOK at them with the
#                        Read tool and score them with references/visual-review-rubric.md.
#
# PDF export is print layout (page size, fit-to-width, margins), not the screen
# grid. Treat audit_layout() as the screen truth and the pages as the print truth.
#
# Never installs anything. Rasterizing uses `pdftoppm` (poppler) or the R
# `pdftools` package when present; otherwise it prints install options and
# returns the PDF paths (the Read tool can open PDFs directly).
#
# Sourcing order: gs_helpers.R, then gs_qa.R (for export_sheet_as_pdf).
# =============================================================================

if (!exists("export_sheet_as_pdf")) stop("Source gs_qa.R before gs_visual_qa.R")

.nz <- function(x, d) if (is.null(x)) d else x
`%||%` <- function(x, y) if (is.null(x)) y else x

# Relative luminance / contrast ratio (WCAG) from Sheets color lists (0-1 floats)
.lum <- function(col) {
  ch <- function(v) { v <- .nz(v, 0); if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055)^2.4 }
  0.2126 * ch(col$red) + 0.7152 * ch(col$green) + 0.0722 * ch(col$blue)
}
.contrast <- function(a, b) { la <- .lum(a); lb <- .lum(b); (max(la, lb) + 0.05) / (min(la, lb) + 0.05) }

# Rough rendered width in px for Arial-like fonts. Deliberately a bit generous:
# a false alarm costs a glance, a missed truncation costs a rebuild.
.text_px <- function(txt, font_size = 10, bold = FALSE) {
  nchar(txt) * font_size * 0.67 * (if (bold) 1.08 else 1) + 8
}

.finding <- function(tab, a1, severity, issue, fix) {
  tibble::tibble(tab = tab, range = a1, severity = severity, issue = issue, fix = fix)
}

#' Audit the on-screen layout of one tab. Returns a tibble of findings
#' (tab, range, severity, issue, fix); zero rows means clean.
#' severity: blocker (content invisible/clipped), major (looks broken), minor (polish).
audit_layout <- function(ss, sheet_name, max_wide_px = 400L, min_narrow_px = 40L) {
  ss_id <- as.character(ss)
  fields <- paste0(
    "sheets(properties(title,gridProperties),merges,",
    "data(columnMetadata(pixelSize,hiddenByUser),rowMetadata(pixelSize,hiddenByUser),",
    "rowData(values(formattedValue,effectiveValue,effectiveFormat(",
    "wrapStrategy,horizontalAlignment,backgroundColor,textFormat(fontSize,bold,foregroundColor))))))")
  req <- googlesheets4::request_generate(
    endpoint = "sheets.spreadsheets.get",
    params = list(spreadsheetId = ss_id, ranges = sprintf("'%s'", gsub("'", "''", sheet_name)),
                  includeGridData = TRUE, fields = fields))
  body <- httr::content(googlesheets4::request_make(req), as = "parsed")
  .audit_sheet(body$sheets[[1L]], sheet_name, max_wide_px, min_narrow_px)
}

# Pure analysis of one parsed `sheets[[i]]` object (unit-testable offline)
.audit_sheet <- function(sh, sheet_name, max_wide_px = 400L, min_narrow_px = 40L) {
  d  <- sh$data[[1L]]
  cols <- d$columnMetadata
  rows <- d$rowMetadata
  col_px <- vapply(seq_along(cols), function(i) {
    if (isTRUE(cols[[i]]$hiddenByUser)) 0 else as.numeric(.nz(cols[[i]]$pixelSize, 100))
  }, numeric(1L))
  row_px <- vapply(seq_along(rows), function(i) {
    if (isTRUE(rows[[i]]$hiddenByUser)) 0 else as.numeric(.nz(rows[[i]]$pixelSize, 21))
  }, numeric(1L))
  a1 <- function(r, c) sprintf("%s%d", col_letter(c), r)

  # width available to a cell = its merge's visible width, else its column
  merge_w <- function(r, c) {
    for (m in .nz(sh$merges, list())) {
      if (r > m$startRowIndex && r <= m$endRowIndex && c > m$startColumnIndex && c <= m$endColumnIndex)
        return(sum(col_px[(m$startColumnIndex + 1L):m$endColumnIndex]))
    }
    col_px[c]
  }
  # first and last column (1-based) of the merge containing a cell
  merge_cols <- function(r, c) {
    for (m in .nz(sh$merges, list())) {
      if (r > m$startRowIndex && r <= m$endRowIndex && c > m$startColumnIndex && c <= m$endColumnIndex)
        return(c(m$startColumnIndex + 1L, m$endColumnIndex))
    }
    c(c, c)
  }

  out <- list(); add <- function(f) out[[length(out) + 1L]] <<- f
  col_has_content <- rep(FALSE, length(cols))
  col_num_align <- vector("list", length(cols))

  for (ri in seq_along(d$rowData)) {
    vals <- d$rowData[[ri]]$values
    for (ci in seq_along(vals)) {
      v <- vals[[ci]]; txt <- v$formattedValue
      if (is.null(txt) || !nzchar(txt)) next
      col_has_content[ci] <- TRUE
      ef <- .nz(v$effectiveFormat, list()); tf <- .nz(ef$textFormat, list())
      fs <- .nz(tf$fontSize, 10); bold <- isTRUE(tf$bold)
      wrap <- .nz(ef$wrapStrategy, "OVERFLOW_CELL")
      is_num <- !is.null(v$effectiveValue$numberValue)
      w <- merge_w(ri, ci); merged <- w != col_px[ci]; need <- .text_px(txt, fs, bold)

      if (col_px[ci] == 0) {
        add(.finding(sheet_name, a1(ri, ci), "blocker", "content in a hidden column",
                     "unhide the column or move the content (first_visible_col())"))
        next
      }
      if (row_px[ri] == 0) {
        add(.finding(sheet_name, a1(ri, ci), "blocker", "content in a hidden row", "unhide the row"))
        next
      }
      if (is_num && need > w) {
        add(.finding(sheet_name, a1(ri, ci), "blocker", sprintf("number needs ~%d px, column is %d px (shows ###)", round(need), round(w)),
                     sprintf("fmt_col_width(sid, %d, %d, %d)", ci, ci, ceiling(need + 10))))
      } else if (!is_num && wrap == "WRAP") {
        lines <- ceiling(need / max(w, 1))
        if (lines * fs * 1.5 > row_px[ri] + 2)
          add(.finding(sheet_name, a1(ri, ci), "major", sprintf("wrapped text needs ~%d lines, row is %d px", lines, round(row_px[ri])),
                       sprintf("fmt_row_height(sid, %d, %d, %d) or widen the column", ri, ri, ceiling(lines * fs * 1.5))))
      } else if (!is_num && need > w) {
        nxt <- if (ci < length(vals)) vals[[ci + 1L]]$formattedValue else NULL
        # text overflows into empty neighbors, but clips against content, a CLIP
        # strategy, or a merge (merged cells never overflow)
        if (merged) {
          span <- merge_cols(ri, ci)
          add(.finding(sheet_name, a1(ri, ci), "blocker",
                       sprintf("text needs ~%d px, merged cells %s:%s are %d px wide and it is cut off",
                               round(need), col_letter(span[1L]), col_letter(span[2L]), round(w)),
                       sprintf("widen columns %s:%s by ~%d px in total, shorten the text, or wrap it",
                               col_letter(span[1L]), col_letter(span[2L]), ceiling(need + 10 - w))))
        } else if (wrap == "CLIP" || (!is.null(nxt) && nzchar(nxt)))
          add(.finding(sheet_name, a1(ri, ci), "blocker", sprintf("text needs ~%d px, column is %d px and is cut off", round(need), round(w)),
                       sprintf("widen col %s to ~%d px, shorten the text, or wrap it", col_letter(ci), ceiling(need + 10))))
      }
      if (row_px[ri] < fs * 1.4 && wrap != "WRAP")
        add(.finding(sheet_name, a1(ri, ci), "major", sprintf("row %d px is shorter than %dpt text", round(row_px[ri]), fs),
                     sprintf("fmt_row_height(sid, %d, %d, %d)", ri, ri, ceiling(fs * 2))))
      bg <- ef$backgroundColor; fg <- tf$foregroundColor
      if (!is.null(bg) && !is.null(fg)) {
        cr <- .contrast(fg, bg)
        if (cr < 3) add(.finding(sheet_name, a1(ri, ci), "major", sprintf("low contrast %.1f:1 (text vs fill)", cr), "darken the text or lighten the fill (aim for 4.5:1)"))
      }
      if (is_num) col_num_align[[ci]] <- c(col_num_align[[ci]], .nz(ef$horizontalAlignment, "DEFAULT"))
    }
  }

  for (ci in seq_along(cols)) {
    if (col_has_content[ci] && col_px[ci] > 0 && col_px[ci] < min_narrow_px)
      add(.finding(sheet_name, sprintf("%s:%s", col_letter(ci), col_letter(ci)), "major",
                   sprintf("column is %d px but holds content", round(col_px[ci])),
                   sprintf("fmt_col_width(sid, %d, %d, 100)  # or keep it empty if it is a gutter", ci, ci)))
    if (col_px[ci] > max_wide_px)
      add(.finding(sheet_name, sprintf("%s:%s", col_letter(ci), col_letter(ci)), "minor",
                   sprintf("column is %d px wide (> %d)", round(col_px[ci]), max_wide_px), "narrow it or wrap the text"))
    al <- unique(col_num_align[[ci]])
    if (length(al) > 1L)
      add(.finding(sheet_name, sprintf("%s:%s", col_letter(ci), col_letter(ci)), "minor",
                   sprintf("numbers in this column use mixed alignment (%s)", paste(al, collapse = "/")),
                   "set halign = \"RIGHT\" on every numeric cell in the column"))
  }
  if (!length(out)) return(.finding(sheet_name, NA_character_, "minor", "", "")[0, ])
  do.call(rbind, out)   # base R: the findings are tibbles with the same columns
}

#' Rasterize a PDF to PNGs (one per page). Returns image paths, or NULL (with
#' install options printed) if neither poppler nor pdftools is available.
pdf_to_pngs <- function(pdf, dpi = 110L) {
  prefix <- sub("\\.pdf$", "", pdf)
  if (nzchar(Sys.which("pdftoppm"))) {
    system2("pdftoppm", c("-r", dpi, "-png", shQuote(pdf), shQuote(prefix)))
    return(sort(Sys.glob(paste0(prefix, "-*.png"))))
  }
  if (requireNamespace("pdftools", quietly = TRUE)) {
    return(pdftools::pdf_convert(pdf, format = "png", dpi = dpi,
                                 filenames = sprintf("%s-%%d.png", prefix), verbose = FALSE))
  }
  message("[visual_qa] No PDF rasterizer found; NOT installing anything. Options:\n",
          "  macOS:   brew install poppler\n",
          "  Debian:  sudo apt install poppler-utils\n",
          "  R:       install.packages(\"pdftools\")\n",
          "Or open the PDF directly (the Read tool accepts PDFs).")
  NULL
}

#' Visual QA for one or more tabs: layout audit + PDF + page images.
#' @param tabs character vector of tab names (NULL = all tabs)
#' @return list(findings = tibble, pdfs = named chr, pages = named list of PNG paths)
#' Then: Read() each PNG, score it with references/visual-review-rubric.md,
#' fix the BUILD SCRIPT (not the sheet by hand), rebuild, re-run. Max 3 loops.
visual_qa <- function(ss, tabs = NULL, out_dir = file.path(tempdir(), "visual_qa"),
                      pause_s = 10, landscape = TRUE) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  tabs <- tabs %||% googlesheets4::sheet_names(ss)
  findings <- list(); pdfs <- character(); pages <- list()
  for (i in seq_along(tabs)) {
    tab <- tabs[i]
    findings[[tab]] <- audit_layout(ss, tab)
    pdf <- file.path(out_dir, paste0(gsub("[^A-Za-z0-9]+", "_", tab), ".pdf"))
    export_sheet_as_pdf(ss, tab, pdf, extra = sprintf(
      "&portrait=%s&size=A4&fitw=true&gridlines=false", tolower(!landscape)))
    pdfs[[tab]] <- pdf
    pages[[tab]] <- pdf_to_pngs(pdf)
    if (i < length(tabs)) Sys.sleep(pause_s)  # export endpoint 429s under bursts
  }
  f <- do.call(rbind, unname(findings))
  message(sprintf("[visual_qa] %d finding(s): %d blocker, %d major, %d minor",
                  nrow(f), sum(f$severity == "blocker"), sum(f$severity == "major"), sum(f$severity == "minor")))
  list(findings = f, pdfs = pdfs, pages = pages)
}
