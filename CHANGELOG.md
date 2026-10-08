# Changelog

## 3.1.0 (unreleased)

First public release. Versions 3.0.0 and 3.0.1 were private; their notes are at the end.

- New reference `build-once-run-forever.md` and a README section: use the model to build,
  keep the script, rerun it with `Rscript` and no model. Inspired by Kelsey Hightower's
  PlatformCon 2026 talk "ZTA: Zero Token Architecture" (credited, paraphrased).
- Understand-first and day-300 guidance, from the full talk transcript.
- README: prominent note to register your own OAuth client or a service account for heavy or team use.
- README: "Getting help" routes skill problems to this repo and asks people not to burden the upstream package maintainers.
- Workflow step 6: hand off the script path and rerun command.
- New eval `handoff-without-model`.

**Fixed**

- `fmt_chart_basic()`, `fmt_chart_bar()`, `fmt_chart_waterfall()`: every call answered
  HTTP 400, because domain and series sources were not wrapped in `sourceRange`. All
  `fmt_chart_*` now build sources through one fixed `.source_range()`.
- `fmt_cells()` (behaviour change): the field mask is per text property
  (`textFormat.fontSize`, `.bold`, `.italic`, `.underline`, `.fontFamily`,
  `.foregroundColorStyle`) instead of the whole `textFormat`. Layered calls merge
  and keep rich-text links. A preset no longer implies a reset: set `bold = FALSE`
  (or the other property) to reset. `apply_style()` inherits this. Only a
  hand-written `repeatCell` with the whole-object mask still wipes a link.
- `f_sumifs()`: an operator criterion such as `">5"` or `">=10"` was left unquoted and
  Sheets answered `#ERROR!`. `quote_criteria()` now quotes it.
- `batch_format()` drops the names of `requests`. A named list (`lapply` over a named
  vector) was sent as a JSON object and answered HTTP 400.
- `write_cell()` (behaviour change): numbers and logicals go out as JSON numbers and
  booleans. As text, `2e6` displayed as `2.00E+06` and on a `de_DE` sheet `"1234.5"`
  was stored as -243129. `NA` writes an empty cell; `Inf`, `NULL` and a value of
  length other than 1 stop. Text starting with `+ - @ '` gets a `'` prefix (a leading
  `+` became a formula and a leading `'` was swallowed); a signed-number string such
  as `"-5"` stays a number. A typed leading `'` is now escaped like any other:
  pass `as_text = TRUE` to keep `"00123"` or `"1/2"` as text. A quote in a tab name
  is escaped. New argument `as_text`.
- `flush_writes()`: new `strict = FALSE`; `TRUE` stops on HTTP 400 and above. The buffer
  is cleared once Google answers, success or error (the batch is all-or-nothing), and
  kept when no answer arrives. The log line says "range writes".
- `fmt_chart_waterfall()` (behaviour change): `subtotal_indices` now marks rows that ARE
  totals (`customSubtotals` with `dataIsSubtotal`); `subtotal_is_data = FALSE` inserts a
  computed subtotal bar instead. `customSubtotals` is omitted when there are no
  indices. `legend` defaults to `NULL` (was `"BOTTOM_LEGEND"`) and passing it warns: the
  API has no waterfall legend field.
- `fmt_slicer()`: removed the `filterSpec` wrapper, which answered HTTP 400 on every
  call; `columnIndex` and `filterCriteria` sit on the spec. `column_index` is an
  absolute 0-based sheet column, not an offset inside `source_range`. The default sends
  no filter criteria. New `filter_criteria` and `apply_to_pivot_tables`; the latter
  applies to all slicers on that data range, the last one created sets it.
- `fmt_protected_range()`: bounds default to `NULL`, which protects the whole sheet,
  the only form that accepts the new `unprotected_ranges`. A partial set of bounds, or
  `unprotected_ranges` on a bounded range, stops with a message instead of an HTTP 400.
- `f_sparkline()`: numbers and logicals are written bare (`"linewidth",3`; the quoted
  form gave `#VALUE!`), strings are quoted with embedded quotes doubled, `I()` writes a
  value verbatim, option names are validated, `NULL` options are dropped.
- `audit_chart_sources(ss_id, sheet_id = NULL)`: `NULL` audits every tab. Each domain and
  series is checked against the hidden columns of the tab it reads, so cross-tab charts
  are covered, as are waterfall and pie charts. A chart left with no series is flagged,
  an HTTP error stops, and sources past the grid no longer crash it with `NA`. Messages
  use column letters. Limit: a partial series loss is not detected.
- `fmt_pivot_table()`: `sortOrder` defaults to `ASCENDING` (the API answers HTTP 400
  "No sort order specified" without one).
- `gs_open_or_create()`: new trailing `time_zone` (default `Sys.timezone()`), `locale`,
  `rows` and `cols`; a reused file gets a message naming any tab it had to add. An
  unnamed `rows` or `cols` vector longer than 1 stops. Earlier calls work unchanged.
- `fmt_dropdown()`, `fmt_dropdown_range()`: new `input_message`.
- `gs_reset_tabs()` resolves `ss` with `as_sheets_id()`, so a URL or dribble works.
- `examples/budget-template.R`, `templates/scenario-engine.R`: `apply_style()` calls
  with no `style` argument aborted; they use `fmt_cells()`.
- Docs corrected: `fmt_cells()` no longer wipes links; the apostrophe advice applies
  only to hand-built `values.batchUpdate` and `range_write()` values; the audit
  catches most cases, not all; retries cover 429, 500, 502 and 503 (gargle 1.5.2),
  not 504; `values.batchGet` with a vector of ranges fails in `request_generate()`;
  the `LET()` scalar-context trap and the zero-denominator guard.

**Safety guards**

- `gs_reset_tabs(ss, tabs, keep_values = FALSE)`: `tabs` is required. Leaving it out,
  `NULL`, `character(0)` or `NA` stops before any API call; there is no "every tab"
  default, so a wrong `SHEET_ID` cannot wipe a whole file by accident. To reset every tab
  pass `googlesheets4::sheet_names(ss)`. An unknown tab name still stops.
- `gs_open_or_create()`: new trailing `allow_mismatch = FALSE`. Reusing an id now reads the
  file's title and tabs first (one `gs4_get()`, replacing the `sheet_names()` call) and
  stops, before adding tabs or writing, when the title is not `title` and the file lacks
  some of `tabs`. A renamed copy that has all the tabs still passes. SKILL.md and a new
  eval say never to set `allow_mismatch = TRUE` without asking the user.
- `gs_open_or_create()` locale guard (behaviour change): on reuse, a non-`NULL` `locale`
  that differs from the file's now stops, naming both, before any change. `NULL` skips the
  check and `allow_mismatch = TRUE` overrides it. Before, `locale` was ignored on reuse.
- Docs and SKILL.md that called `gs_reset_tabs(ss)` with no tabs now pass the tab names.

**New helpers**

- `gs_reset_tabs(ss, tabs, keep_values = FALSE)` (`tabs` required, see Safety guards): blank slate for rerunning a
  build in place (charts, slicers, tables, banding, protections, filter views,
  conditional rules, groups, named ranges, filter, merges, validation, notes, pivots,
  formats, values, hidden rows and columns, sizes, freezes).
- `read_values(ss, ranges, value_render)`: A1 ranges as matrices, one retried
  `values.get` per range.
- `write_block(ss, sheet, row, col, x, as_text)`: a matrix, data.frame or vector as
  one buffered range.
- `fmt_basic_filter()`: `setBasicFilter`.
- `fmt_cond_formula()`, `fmt_cond_text_equals()`, `fmt_cond_number()`: conditional
  rules with `index` for priority.
- `fmt_chart_pie()`: pie, and doughnut with `donut = TRUE`.
- `fmt_chart_*`: `anchor_sheet_id` places a chart on a different tab than its data;
  `fmt_chart_basic()` adds `x_title`, `y_title` and per-series `line`, `point`, `label`;
  `fmt_chart_waterfall()` adds `subtotal_labels`, `subtotal_label`, `subtotal_is_data`
  and `data_labels`.
- `fmt_validation()`: `setDataValidation` for number, date, text and custom-formula rules
  (`NUMBER_BETWEEN`, `NUMBER_GREATER_THAN_EQ`, `DATE_IS_VALID`, `CUSTOM_FORMULA`,
  `TEXT_IS_EMAIL`, ...), with `input_message` and `strict`. Checks type, value count and
  a leading `=` before any call.
- `fmt_cond_text(op = equals | starts_with | contains | not_contains)`;
  `fmt_cond_text_equals()` delegates to it. `fmt_cond_color_scale()` gained `index`.
- `fmt_cells()`: new trailing `numfmt = list(type, pattern)` (the `NUMFMT_*` constants).
  Giving it together with `numfmt_type` or `numfmt_pattern` stops.
- `fmt_tab_order(ss, tabs)`: one `updateSheetProperties` (index) request per tab.
- `fmt_theme_colors()`: spreadsheet theme palette (pie and doughnut slice colours). The API
  accepts only a complete theme, so omitted colours reset to Google's defaults.
- `fmt_chart_basic()`, `fmt_chart_bar()`, `fmt_chart_waterfall()`, `fmt_chart_pie()`: new
  `offset_x`, `offset_y` and `style = list(font, title_size, title_bold, title_color,
  title_position, background, border, axis_font_size)`; `fmt_chart_basic()` also takes
  `y_min` and `y_max` (explicit axis window). `y2_title`, `y2_min`, `y2_max` and
  `style$legend_font_size` are accepted but have no effect (the Sheets API drops RIGHT_AXIS
  settings and has no legend text size) and warn.
- `color_to_hex()`: API colour list to `"#RRGGBB"`. `f_sparkline(iferror = )` wraps the
  formula in `IFERROR(..., "")`.
- `gs_clear_values(ss, range_or_sheet)`: clear values only, one `values.clear` call; the
  formatting stays (`range_clear()` resets it by default).
- `fmt_col_widths(sheet_id, widths, start_col = 1L)`: widths for a run of columns in one call.
  Equal neighbours merge into one request, widths round to whole pixels (the API rejects a
  fraction), and it returns a list, so combine it with `c()`.
- `fmt_note(sheet_id, row, col, text)`: a cell note through `updateCells` with the mask `note`
  alone, so the value and format stay; `""` clears it.
- `new_batch()`: request collector with `$push()`, `$cf()` and `$get()`. `$cf(f, sheet_id, ...)`
  numbers conditional rules per tab from 0, so the rule listed first wins.
  `fmt_cond_negative()` gained the trailing `index` the other rule helpers already had.
- `gs_count_objects(ss_id)`: one read-only call that counts charts, conditional rules,
  validated cells, protections, filter views, slicers, bands, merges, notes and frozen
  rows and columns per tab, to compare a file before and after a rebuild.

**Docs, evals and tooling**

- New pitfalls rows: API writes bypass data validation; `COUNTIFS(range, "*")` matches
  text only and skips blanks (use `"<>x"`); formulas that return `""` sort first in a
  descending sort; `f_safe_div()` returns `""` and hides spend against a zero budget;
  `range_clear()` resets formats; `write_block()` with a character matrix sends numbers as
  text and drops percent and date number formats (checked live); AREA charts can drop the
  last x-axis label when narrow; pivot-table labels render italic; PDF export repeats
  frozen rows (`&fzr=false` in `extra` stops it, checked) and the API has no print setup. The `gs_reset_tabs()` rows use the new signature.
- `qa-post-build.md`: "Flip-and-restore test" recipe (snapshot, flip, read, restore with
  `on.exit()`, confirm with a read; test scripts must never leave a sheet changed).
- `drive-integration.md` and `SECURITY.md`: what a shared sheet exposes (owner name to
  link viewers, owner stored as editor on protected ranges, view-only
  visitors cannot use dropdowns, link-shared sheets can be indexed).
- `charts.md`, `data-validation.md`, `conditional-formatting.md`, `creating-and-tabs.md`,
  `formatting-batchupdate.md`: sections for the new helpers and arguments.
- SKILL.md: bullets on the title guard and on the data-tab / presentation-tab dashboard
  pattern (`anchor_sheet_id`).
- `helpers.md` now has a row for every helper, including `gs_require_level()` and
  `write_section_header_brand()`, which had none.
- `scripts/check.sh`: new doc-drift gate. It fails when a function in `scripts/*.R` has no
  row in `references/helpers.md`, parses every R file under `skills/`, `examples/` and
  `scripts/`, checks that SKILL.md links to reference files that exist, and checks that
  `plugin.json`, SKILL.md and this file name the same version.
- `scripts/selftest.R`: live self-test of the helpers on one scratch sheet at the default
  access level, with a PASS/FAIL table. A repo dev tool, not part of the skill folder.
  Checks cover the four new helpers (read back from Google) and the locale guard, which
  flips the scratch file's locale and restores it.
- `helpers.md`, `creating-and-tabs.md`, `formatting-batchupdate.md`,
  `conditional-formatting.md`, `qa-post-build.md`, `api-endpoints.md`: the new helpers and
  the locale guard. `helpers.md` also notes the Sheets read quota (about 60 read requests per
  minute per user, one call per range in `read_values()`, so large loops can hit HTTP 429).
- Four new evals (13 to 17): `reuse-wrong-file`, `flip-and-restore`, `cross-tab-chart`,
  `share-exposure`. All 17 were graded as dry runs on Haiku; the four new ones also on
  Sonnet and Opus.
- `scripts/offline-test.R`: checks that need no Google account (request shapes, formulas,
  value escaping, and the guards that must stop before any request). It runs in CI on every
  push and pins each shape an earlier live test showed Google rejects or misreads.
- CI: read-only token, full-history checkout for the secret scan, third-party actions pinned
  to commit SHAs, Dependabot for actions, and a job that runs the offline tests.
- `gs_setup.sh` also looks for Rscript under `Program Files\R\R-*\bin` (newest version
  first), because the CRAN installer for Windows does not put R on PATH. Untested on a real
  Windows machine; `scripts/check.sh` tests the lookup on a fake tree.
- Issue forms, a pull request template, a code of conduct and a Dependabot config.
- Showcase `saas-model.R`: Unit Economics CAC falls back to the CAC input when a year has no
  new customers, so "Model ties" stays OK when month-1 new customers is set to 0.
- SKILL.md: the sharing note gives the exact `GS_SCOPE_LEVEL=drive` sign-in command.
- `visual_qa()` and `audit_layout()` combine their findings with base `rbind()`. They used
  `dplyr::bind_rows()`, and dplyr is not one of the packages the setup script installs, so a
  fresh R install stopped at the first run that had findings.
- Credits name Lucy D'Agostino McGowan for googledrive in the README, SKILL.md and the site.

## Before the public release

### 3.0.1 (private)

- **Fix:** `audit_layout()` now reports a clipped merged title as "merged cells A:D are
  N px wide" and suggests widening the merged columns in total (it used to suggest
  widening one column to the full text width).
- New `gs_open_or_create()`: rebuild into the same sheet with `SHEET_ID=<id>` instead of
  leaving a new file in Drive on every fix loop. Templates and examples use it.
- SKILL.md and the review rubric: state only what you observed (do not describe page
  images or scripts you did not read).
- A clear user instruction to install what is needed counts as consent for the three CRAN
  packages (never for R, access levels, sharing or the account choice).
- Evals: forbidden-action expectations added, and six new cases (blanket "just install",
  background sign-in, blocked port, injection in a tab name, missing rasterizer, cron).

### 3.0.0 (private)

First version prepared for release.

- Employer-specific branding removed; `brand.R` is a generic, editable theme.
- **Least-privilege auth:** default access level is `spreadsheets`; `readonly`,
  `export` and `drive` are opt-in (`GS_SCOPE_LEVEL`).
- **Visual QA built in:** `audit_layout()` and `visual_qa()` (layout audit, PDF
  export, page images) plus a review rubric. No separate reviewer skill needed.
- Never installs R; asks before installing R packages; prints OS-specific R install options.
- SKILL.md rewritten for progressive disclosure (under 250 lines), portable paths, MIT license.
- Third-party credits and security policy added.
