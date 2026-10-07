# Pre-Build Dump — regenerating a reference tab identically

When the task is *"regenerate this approved tab identically"* against
a snapshot, the temptation is:

1. Read col B/C/D labels with `read_sheet()` to map sections.
2. Sample a couple of formulas with `userEnteredValue.formulaValue`.
3. Start writing R code based on that mental model.
4. Build, run, get "33/33 QA passing", declare done.
5. User reviews → flags missing dashed border, wrong subtotal highlight,
   missed gradient, off-by-one merged gutter. Rebuild. Repeat.

**The skipped step is per-cell formatting.** Labels + formulas convey
70-80% of the structure but 0% of the visual contract. The other
20-30% — borders, fills, fonts, number formats, merged ranges, hidden
rows, frozen panes, conditional formats — is what makes the rebuilt
tab read as "the same tab" to a reader.

Misses typically caught only after a user flags them:

- Subtle DASHED right border on col G (Mar'26) acting as the
  actual-vs-forecast separator.
- Lavender (`#E8EAF6`) backgrounds on Net Cash from Operations / Net
  Change / Closing Bal / Effective Cash that signal "this is a total".
- `#993300` red foreground on COGS / OPEX / Total OPEX / Net Op CF
  rows. Lost in rebuild → reads as plain text.
- A distinct deeper blue (vs the section headers' standard blue) on a
  sensitivity-matrix banner.
- Two separate gradient conditional formats on the §6 heatmap with
  different grain.
- Blue text (`#0000FF`) on Q1 Trend column and yellow-input cells,
  marking "live-linked / editable".
- Two distinct brand shades used inconsistently (standard vs a deeper
  shade meant for a second-level banner only).

**Content correctness was checked, format contract was not.**

## The rule

> For any "regenerate this tab identically" task, your first action is
> to dump the reference tab's full visual contract — values + formulas +
> `effectiveFormat` (every attribute) + merges + hidden rows + frozen
> panes + column widths + conditional formats — in ONE pass, save it to
> a temp file, and treat that file as the source of truth. Do not start
> writing R code until you have it.

## Use `dump_reference_tab()`

```r
source("scripts/gs_qa.R")

dump_reference_tab(SS_ID, "Reference Tab Name", "A1:AF500",
                   "/tmp/ref_dump.txt")
```

The output file has:

- One header line with `frozenRows` / `frozenCols`.
- One `MERGE rows X..Y cols A..B` line per merged range.
- One `CF GRADIENT|BOOLEAN rows X..Y cols A..B` line per conditional
  format.
- One `HIDDEN_ROW N` line per hidden row.
- One `COL N width=X hidden=Y` line per column with non-default width
  or hiding.
- One `R{row} C{col} | {value} | bg=… fg=… B?I? fs=… ha=… nf=… bd[…]`
  line per non-default cell.

## The workflow

1. **Dump first**, before any R code:

   ```r
   dump_reference_tab(SS_ID, "Reference Tab Name", "A1:AF500",
                      "/tmp/ref_dump.txt")
   ```

2. **Read the file before coding.**

   ```bash
   cat /tmp/ref_dump.txt | grep "R125 "
   ```

   See every cell on row 125. Don't reach for `read_sheet()` — you have
   the full payload already.

3. **Don't paraphrase from the dump.** If the user put a `DASHED/#434343`
   left border on col H of every row in offsets 4..26, that's the spec —
   reproduce it literally. Don't substitute "a thin gray separator"
   because the API supports DASHED but you reached for SOLID.

4. **Diff after each section.** Re-run `dump_reference_tab` against
   your own tab after each section's writes flush. Compare line-by-line.
   If §6 has 50 cell-format lines in the reference and your generated
   dump has 30, you missed formatting — find the missing 20 before
   moving to §7.

5. **For long-form text cells (explainers, footnotes), match newlines
   exactly.** R string literals don't preserve `\n` from the API dump
   automatically — explicitly insert `\n` where the reference has them.

6. **Snapshot-match or live-recompute?** If the reference shows `$1.5M`
   because Q1 actuals were a specific number on a specific day, your
   live formula will drift to `$1.2M` next week. Either hardcode the
   snapshot values or accept drift — and tell the user which you chose.

## What NOT to do

- ❌ "Let me read the labels and start building." — Misses 30% of the
  visual contract.
- ❌ "QA passed; the values match." — QA is a formula-correctness check,
  not a visual-contract check.
- ❌ "I'll add formatting later when I see what's missing." — You'll
  see what's missing only after the user reviews. By then you've
  already delivered.
- ❌ Reading `effectiveFormat` only on cells where you suspect a
  difference. You don't know what to suspect until you've seen the
  full dump.

## One-line summary

When asked to regenerate a reference tab, **the dump is the spec.**
Pull it first, read it before coding, diff against it after each
section. See [qa-post-build.md](qa-post-build.md) for the
complementary post-build visibility checks.
