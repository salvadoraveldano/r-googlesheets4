# Helper Cheat Sheet

Every helper shipped in `scripts/`. Source order and the few that matter most are in SKILL.md.

| Helper                  | File              | What it does                                                      |
|-------------------------|-------------------|-------------------------------------------------------------------|
| `gs_open_or_create(title, tabs)` | gs_helpers.R | Create the sheet, or reuse the one in `SHEET_ID` (adds missing tabs). Use it so each rebuild edits one file instead of orphaning a new one |
| `gs_connect()`          | gs_helpers.R      | Auth googlesheets4 + googledrive from the login saved by `gs_setup.sh` (arg → `GS_EMAIL` → config file); fails fast with the fix command, never opens a browser |
| `hex_to_color()`        | gs_helpers.R      | Hex string → API 0-1 float RGB color                              |
| `grid_range()`          | gs_helpers.R      | 1-based row/col → 0-based GridRange                               |
| `col_letter()`          | gs_helpers.R      | Column index → A1 letter(s)                                       |
| `get_sheet_id()`        | gs_helpers.R      | Tab name → numeric sheetId                                        |
| `fmt_cells()`           | gs_helpers.R      | repeatCell — font, fill, numfmt, alignment                        |
| `fmt_merge()`           | gs_helpers.R      | mergeCells (⚠ can't span a frozen column — see gotcha #6)         |
| `fmt_unmerge()`         | gs_helpers.R      | unmergeCells — pair with `fmt_merge()` (unmerge→merge) to re-apply merges idempotently |
| `fmt_borders()`         | gs_helpers.R      | updateBorders — top/bottom/left/right/inner                       |
| `fmt_gridlines()`       | gs_helpers.R      | Hide/show gridlines on a sheet                                    |
| `fmt_freeze()`          | gs_helpers.R      | Freeze top N rows or left N cols                                  |
| `fmt_tab_color()`       | gs_helpers.R      | Tab color in the bottom strip                                     |
| `fmt_col_width()`       | gs_helpers.R      | Column width in pixels                                            |
| `fmt_row_height()`      | gs_helpers.R      | Row height in pixels                                              |
| `fmt_auto_resize_rows()`| gs_helpers.R      | Auto-fit row heights to wrapped content (overrides pinned heights — place LAST in batch) |
| `link_cells_req()` ⚠   | gs_helpers.R      | Column of label cells with REAL rich-text links — the only reliable way to write clickable links (API-written `=HYPERLINK()` is dead on first click, gotcha #9). Apply AFTER all formatting |
| `parse_hyperlink()`     | gs_helpers.R      | `=HYPERLINK("url","label")` content string → list(url, label) — migrate formula links to `link_cells_req()` |
| `fmt_group_cols()` ⚠   | gs_helpers.R      | Group + hide columns (returns 2 requests — use `c()` not `list()`) |
| `fmt_group_rows()` ⚠   | gs_helpers.R      | Group + hide rows (returns 2 requests — use `c()` not `list()`)    |
| `fmt_dropdown()`        | gs_helpers.R      | Data-validation dropdown from a list (renders as **Arrow** — see [data-validation.md](data-validation.md) for chip-style via Tables API) |
| `fmt_dropdown_range()`  | gs_helpers.R      | Dropdown sourced from a sheet range (ONE_OF_RANGE)                |
| `fmt_named_range()`     | gs_helpers.R      | addNamedRange                                                     |
| `fmt_cond_negative()`   | gs_helpers.R      | Red-text rule for negative values                                 |
| `fmt_cond_color_scale()`| gs_helpers.R      | Gradient rule (green → yellow → red)                              |
| `batch_format()`        | gs_helpers.R      | Send a list of requests in ONE batchUpdate (logs HTTP status; `strict=TRUE` stops on ≥400) |
| `write_cell()`          | gs_buffer.R       | Buffer one cell write (no API call)                               |
| `flush_writes()`        | gs_buffer.R       | Flush all buffered writes in ONE values.batchUpdate               |
| `clear_writes()`        | gs_buffer.R       | Empty the buffer without flushing (abort a partial build)         |
| `apply_style()`         | gs_buffer.R       | Apply a `STYLE_*` preset with optional overrides                  |
| `write_section_header()`| gs_buffer.R       | Buffered section-header writer + format requests                  |
| `STYLE_BODY` etc.       | gs_buffer.R       | Reusable style bundles                                            |
| `first_visible_col()`   | gs_qa.R           | First non-hidden column (use before placing title text)           |
| `audit_chart_sources()` | gs_qa.R           | Warn for charts whose source range overlaps hidden cols           |
| `audit_merge()`         | gs_qa.R           | Check a merged range has enough visible width                     |
| `count_cond_rules()`    | gs_qa.R           | Count existing conditional rules (always check before deleting)   |
| `fmt_delete_cond_rules()`| gs_qa.R          | Delete ALL existing cond rules (counts first, deletes descending) — for idempotent re-runs |
| `dump_reference_tab()`  | gs_qa.R           | Dump a tab's full visual contract — pre-build spec for regeneration |
| `safe_locale_date()`    | gs_qa.R           | Format a date in English regardless of LC_TIME                    |
| `parse_num()`           | gs_qa.R           | Strip `$` / commas / `%` → numeric (robust parse of read-back text cells) |
| `export_sheet_as_pdf()` | gs_qa.R           | Export one tab to a local PDF (print layout) |
| `audit_layout()`        | gs_visual_qa.R    | On-screen layout audit of one tab: truncated text, `###`, narrow/wide cols, short rows, hidden content, contrast → findings tibble |
| `visual_qa()`           | gs_visual_qa.R    | Layout audit + PDF export + page PNGs for every tab; then follow [visual-review-rubric.md](visual-review-rubric.md) |
| `pdf_to_pngs()`         | gs_visual_qa.R    | Rasterize a PDF with `pdftoppm`/`pdftools` if present (never installs) |
| `f_sumifs()`            | gs_formulas.R     | Generic SUMIFS builder                                            |
| `f_safe_div()`          | gs_formulas.R     | `IF(denom=0,"",num/denom)` — avoid #DIV/0!                        |
| `f_iferror()`           | gs_formulas.R     | Wrap an expression in IFERROR with a fallback                     |
| `f_named()`             | gs_formulas.R     | Interpolate named-range refs into a formula (`{driver}` placeholders) |
| `fraw()`                | gs_formulas.R     | Strip leading `=` to combine formula builders without `==`        |
| `f_query()`             | gs_formulas.R     | QUERY formula builder                                             |
| `f_sparkline()`         | gs_formulas.R     | SPARKLINE formula with options (Sheets-only)                      |
| `fmt_chart_basic()`     | gs_charts.R       | LINE / COLUMN / AREA / SCATTER / COMBO chart                      |
| `fmt_chart_bar()`       | gs_charts.R       | BAR (horizontal) chart with BOTTOM_AXIS forced                    |
| `fmt_chart_waterfall()` | gs_charts.R       | Waterfall chart                                                   |
| `fmt_banding()`         | gs_modern.R       | Banded range — alternating row colors                             |
| `fmt_pivot_table()`     | gs_modern.R       | Pivot table at an anchor cell                                     |
| `fmt_filter_view()`     | gs_modern.R       | Saved per-user filter view                                        |
| `fmt_protected_range()` | gs_modern.R       | Lock a range from edits                                           |
| `fmt_slicer()`          | gs_modern.R       | Slicer chip (filters charts/pivots)                               |
| `fmt_image_cell()`      | gs_modern.R       | Embed an image via `=IMAGE()` or overlay                          |
| `fmt_find_replace()`    | gs_modern.R       | Bulk find/replace across a sheet/spreadsheet                      |
| `fmt_auto_resize_cols()`| gs_modern.R       | Auto-fit column widths to content (batchable)                     |
