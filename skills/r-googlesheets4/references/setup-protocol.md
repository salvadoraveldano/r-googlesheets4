# Setup Protocol (Step 0)

Agents run R non-interactively (`Rscript`), so the usual `gs4_auth()` browser
flow cannot start from a build script. `scripts/gs_setup.sh` handles it. Run it
from the skill directory before writing any sheet code:

```bash
bash scripts/gs_setup.sh status
```

Branch on the final `GS_SETUP state=…` line (mirrored by the exit code).

| state | What to do |
|---|---|
| `READY` | Continue. Scripts start with `source(file.path(SKILL, "scripts", "gs_helpers.R")); gs_connect()`. |
| `NEEDS_R` | R is not installed. **Never install it.** Relay the options the script printed (CRAN installer, rig, Homebrew, Posit Linux packages, or [no-r-alternatives.md](no-r-alternatives.md) for people who will not install R) and stop until the user has installed it. |
| `NEEDS_INSTALL` | Name the missing packages, explain they come from CRAN (2–5 min), and **get an explicit yes before running `gs_setup.sh install`** (run it in the background). A user instruction that clearly says to install what is needed ("just install it, don't ask") counts as that yes for these CRAN packages only: still name them first. It never covers installing R, raising the access level, sharing, or choosing an email. On exit: `INSTALLED` → re-run `status`. `NEEDS_INSTALL` again (`next=fix-system-deps`) → do **not** run `install` again: relay the "Still missing after install" line and its hint (Linux system libraries, or `GS_LIB=~/R/library` when no library is writable); stop until the user has fixed it. |
| `NEEDS_EMAIL` | Use an email the user already gave in this conversation; otherwise ask: "Which Google account (email) should I use for Google Sheets?" If the line lists `cached=` accounts, offer them as options. Never guess. If `reason=invalid-or-missing-email`, the value was not an email address: say so and ask again. Then: if `cached=` lists that account at the current access level, run `gs_setup.sh auth <email>` (silent, no browser); otherwise treat it as `NEEDS_AUTH`. |
| `NEEDS_AUTH` | Tell the user: "I'll open a Google sign-in page for <email>. Pick that account and click **Allow** (access level: <level>). The tab will say 'Authentication complete'; come back here and I'll continue. The login is saved on this computer, so this happens once." Run `gs_setup.sh auth <email>` in the background (the wait for the click has no fixed length). A few seconds later read its output and **always relay the `https://accounts.google.com/…` link it printed** ("a Google tab should have opened; if it didn't, open this link in a browser on this same computer while I wait"). If the output says `BROWSER_NOT_OPENED`, say no browser could be started and they must open the link themselves. Only hand out the link from the run that is currently waiting; a link from an exited run is dead. On exit: `READY` → say "Connected as <email>" (if `reason=mismatch`, say which account was actually saved). `NEEDS_AUTH reason=token-revoked` → the saved login was dead and has been removed; explain, then run `auth` again. `AUTH_FAILED` → relay the `[gs_setup]` line and branch on `reason=` (below). |
| `AUTH_FAILED` reasons | `in-progress`: do not start another `auth`; a sign-in is already waiting in a browser tab, ask the user to finish it, then re-run `status`. `timeout` / `denied` / `other`: repeat the `NEEDS_AUTH` row at most **once**, then stop and relay. `port` (loopback listener blocked by a firewall/sandbox) / `network` (fix connectivity, then `gs_setup.sh verify`) / `verify-failed` (Google accepted the sign-in but refuses the API call for this account): do not re-run `auth`; relay and stop. |
| `ERROR`, or the task exits with **no** `GS_SETUP` line (killed / timed out) | Do not retry blindly: relay the last `[gs_setup]` line. For an `auth` that was killed, follow the `NEEDS_AUTH` row again once the user is ready. |

## Access levels

The default level asks for the narrowest access that works. Raise it only when
the task needs it, and only after the user agrees.

| `GS_SCOPE_LEVEL` | Google scope(s) | Needed for |
|---|---|---|
| `sheets` (default) | `spreadsheets` | create, read, write and format sheets |
| `readonly` | `spreadsheets.readonly` | read-only analysis |
| `export` | `spreadsheets` + `drive.readonly` | finding sheets by name (PDF export for visual QA already works at the default level) |
| `drive` | `drive` | also share, move, copy, delete files (`drive_share()`, etc.) |

To change level: `GS_SCOPE_LEVEL=export bash scripts/gs_setup.sh auth <email>`, and
set the same variable for the build script. Tokens for different levels live side
by side in the cache and never overwrite each other. Helpers that need more
access stop with the exact command (`gs_require_level()`).

## Rules

- Generated scripts call `gs_connect()`. Never call `gs4_auth()` / `drive_auth()`
  directly and never start auth from inside a build script (it cannot complete
  there; `gs_connect()` fails fast with the fix command instead).
- While `gs_setup.sh auth` waits in the background, do **not** run `status`,
  another `auth`, or any R that calls `gs_connect()`: they would report "no saved
  login" (or `reason=in-progress`) and tempt a second sign-in tab. Wait for the
  task to exit, then branch on its last `GS_SETUP` line.
- If `gs_connect()` (or any build script) stops with "Run once … gs_setup.sh auth
  <email>", treat it exactly as the `NEEDS_AUTH` row. Never run `auth` in the
  foreground: shell tools kill it at about two minutes while the sign-in waits up
  to five, and the tab dies with it. If it stops with "Could not reach Google" the
  login is fine; it is a network problem, so do not run `auth`.
- "Use my work account" → `gs_connect("me@example.com")` in that script. If that
  account has no saved login, run `gs_setup.sh auth me@example.com` once, following
  the `NEEDS_AUTH` row; the default account is unchanged.
- Cron / unattended refresh: the saved login refreshes itself for the same OS
  user, or set `GS_SA_JSON=/path/key.json` for a service account. Details and
  troubleshooting: [auth.md](auth.md).
