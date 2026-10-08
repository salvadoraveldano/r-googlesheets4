# Build once, run without a model

The model is most useful when it *builds* the sheet. It should not be needed to
*run* it every day. This skill writes an R script, and the script is the thing you
keep: it rebuilds or refreshes the sheet with no model and no tokens.

This lines up with a PlatformCon 2026 talk by Kelsey Hightower,
[ZTA: Zero Token Architecture](https://www.youtube.com/watch?v=A7WFt2JQ5sg). His
one-sentence version: "Infer once, export, and run without inference." He predicts
a move from burning tokens in a loop to using them once to create the loop, then not
using inference again until the loop changes. His other point is that you should
understand the thing you are doing before you hand it to a model. See also Greg
Herlein's [Tokens Should be NRE, Not COGS](https://blog.herlein.com/post/tokens-are-nre-not-cogs/).
The talk is about platform engineering, not spreadsheets. This page applies the idea
to this skill and is not endorsed by either author.

## The pattern

1. **Build with the model.** Describe the sheet. The agent writes and tests `build.R`
   (design, formulas, formatting, visual QA).
2. **Keep the script.** Put it in version control. It is the exported artifact.
3. **Run it without a model.** `Rscript build.R` rebuilds. `SHEET_ID=<id> Rscript build.R`
   rebuilds into the same sheet ([helpers.md](helpers.md), `gs_open_or_create()`).
   Schedule it with cron or CI ([auth.md](auth.md)).

## Make a build model-free

- Parameters (month, input CSV path, sheet id) at the top of the script or in env vars.
- Formulas stay as formulas in the sheet, so people can read and edit them by hand.
- No secrets in the script. Sign-in comes from the saved login or `GS_SA_JSON`.
- `SHEET_ID` for in-place rebuilds, so refreshes do not create new files, and
  `gs_reset_tabs(ss, TABS)` at the start so a rerun does not stack charts or hit "already exists".
- A header comment: what it builds, the exact rerun command, which inputs it reads.
- Run `visual_qa()` once at build time. Routine refreshes of the same layout do not
  need it again, only when the layout changes.

## Understand what you ship

Outsourcing the build is fine once you know what you are asking for. At hand-off the
agent gives a plain-language walkthrough: what the script reads, what each tab is for,
and where the key formulas live. The team then runs the script once themselves
(`Rscript build.R`) before relying on it, so the first rerun is not a surprise.

## Day 300 check

Look past launch day. Could someone on your team rebuild this sheet, or fix a broken
column, if no model were available? If not, the hand-off is not finished: add a header
comment, simplify the script, or write down the one command that matters. A team that
cannot work when tokens are unavailable has swapped one dependency for another.

## Honest limits

- A finished sheet and its script run without a model. **Changing the design** still
  needs a person (or a model) to edit the script.
- A sheet nobody understands is still a risk. Keep the script readable and the
  formulas visible; the point is that your team can maintain it.
- Refresh scripts still depend on Google's API, quotas and the saved login or key.
