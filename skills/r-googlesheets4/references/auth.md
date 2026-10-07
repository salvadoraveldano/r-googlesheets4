# Authentication & Scopes

How the skill connects to Google — and what to do when it doesn't.

## The short version

- **One-time setup** (per computer, per Google account). Opens the Google
  sign-in page, waits for **Allow**, verifies the Sheets API, saves the account
  as the default:

  ```bash
  bash scripts/gs_setup.sh auth you@example.com
  ```

- **Every script** starts with:

  ```r
  source("scripts/gs_helpers.R")
  gs_connect()                  # or gs_connect("other@example.com")
  ```

  `gs_connect()` reuses the saved login, authenticates googlesheets4 (and
  googledrive at the `export` and `drive` access levels), never opens a browser,
  and fails fast with the exact setup command when a login is missing.

- [setup-protocol.md](setup-protocol.md) tells the agent how to drive this automatically
  (`status` → `install` → ask for the email → `auth` → continue).

## Why a setup command instead of `gs4_auth()` in the script

Claude Code runs R through `Rscript`, a **non-interactive** session, and there:

- gargle refuses to start OAuth ("OAuth2 flow requires an interactive session"),
- httr only *prints* the consent URL instead of opening the browser,
- gargle would ask "Is it OK to cache OAuth access credentials…?" on a console
  nobody can answer (and, un-asked, would not cache the token at all),
- the wait for the browser redirect has no timeout.

`scripts/gs_setup.R auth` handles all of that: it flips gargle's interactivity
switch (`options(rlang_interactive = TRUE)`), opens the URL itself (`open` /
`xdg-open`; the link is always printed as a fallback), passes an explicit cache
path, falls back to a free port if 1410 is taken, times out (default 300 s,
`GS_AUTH_TIMEOUT`), verifies with live calls to **both** API hosts
(`drive_user()` on www.googleapis.com and a read of a public example sheet on
sheets.googleapis.com), and saves the account. Build scripts must never try to
authenticate on their own.

## `gs_setup.sh` reference

| Command | What it does | Network |
|---|---|---|
| `status [email]` | Packages present? Which account? Is there a saved login at the current access level for it? Lists saved logins as `cached=…`. When given an email, READY, and no default saved yet, saves that email as the default. | no |
| `install` | `install.packages()` for the missing packages (CRAN binaries preferred). Run in the background — minutes. | yes |
| `auth [email]` | Google sign-in for that account (default: the saved one; silent if a valid login already exists), verify, save the account Google reports as default. Run in the background — waits for the click. Refuses to start while another `auth` is waiting (`reason=in-progress`). | yes |
| `verify [email]` | Runs `gs_connect()` + a live Sheets-host read (plus `drive_user()` at the Drive levels). With `GS_SA_JSON` set, checks the service account instead. | yes |

The **last stdout line** is machine-readable:

```
GS_SETUP state=<STATE> email=<x|-> reason=<..|-> next=<command|-> [cached=a@x(sheets),b@y(other-scopes)]
```

| state | exit | Meaning / next step |
|---|---|---|
| `READY` | 0 | Saved login at the current access level exists (or auth just succeeded). |
| `INSTALLED` | 0 | `install` finished. Re-run `status`. |
| `NEEDS_R` | 2 | No `Rscript` found. Install R (https://cloud.r-project.org). |
| `NEEDS_INSTALL` | 3 | `reason=` lists missing packages. Run `install` once. If `install` itself ends in `NEEDS_INSTALL` (`next=fix-system-deps`), a package failed to build — fix the system dependency / library permission first; do not loop. |
| `NEEDS_EMAIL` | 4 | No account given/configured (`reason=-`), or the value was not an email (`reason=invalid-or-missing-email`). Ask the user, then `auth <email>` (silent when `cached=` already lists it at the current level). |
| `NEEDS_AUTH` | 5 | `reason=no-saved-login` / `token-lacks-scope` (from `status`), `gs_connect-failed` (from `verify`), `token-revoked` (from `auth`: the saved login was dead and has been removed). Run `auth <email>` — for `token-revoked` it will open the browser, so explain first. |
| `AUTH_FAILED` | 6 | `reason=timeout` / `denied` / `other` → re-run `auth` at most once. `in-progress` → finish the sign-in that is already waiting. `port` → a firewall/sandbox blocks the loopback listener. `network` → fix connectivity, then `verify`. `verify-failed` → Google accepted the sign-in but refuses the API call for this account. `service-account` (`next=fix-GS_SA_JSON`) → `GS_SA_JSON` is missing or not a usable key; fix the path/key, then `verify`. |
| `ERROR` | 1 | `reason=unknown-command` / `helpers-missing`. |

`reason=mismatch` on `READY` means the user picked a different Google account in
the browser than requested; the account actually signed in was saved. `cached=` is
printed by `status` only. Emails are lower-cased everywhere (that is how gargle
names its cache files).

Environment overrides (tests and unusual setups):

| Variable | Effect |
|---|---|
| `GS_EMAIL` | Account to use when none is given (`gs_connect()` and `gs_setup.sh`). |
| `GS_CONFIG` | Path of the file holding the default account. |
| `GS_OAUTH_CACHE` | Token cache directory. |
| `GS_SA_JSON` | Service-account key → `gs_connect()` uses it instead of a user login. |
| `GS_LIB` | Library to install packages into. |
| `GS_AUTH_TIMEOUT` | Seconds to wait for the browser sign-in (default 300). |
| `GS_NO_BROWSER=1` | Never launch a browser (link is still printed). |

## `gs_connect()` reference

```r
gs_connect(email = NULL, quiet = FALSE)   # returns the email invisibly
```

1. `GS_SA_JSON` set → service-account auth for both packages (the key is
   validated and checked live; a missing/invalid key stops with a clear message
   instead of falling back to a user login).
2. Account = `email` argument → `GS_EMAIL` → `~/.config/r-googlesheets4/email`.
   None → stops: *"No Google account configured… Run once: … auth you@example.com"*.
3. Looks for a saved token for that account **with the scopes of the current
   `GS_SCOPE_LEVEL`**. None → stops: *"No saved Google login for <email> with the
   requested access (sheets). Run once: … auth <email>"*. It never guesses from other cached accounts and
   never opens a browser.
4. `gs4_auth(email, scopes = <level scopes>, cache)` from the cache. At the
   `export` and `drive` levels the same token also authenticates googledrive.
5. One live call (`gs4_user()` at the Sheets levels, `drive_user()` at the Drive
   levels; `auth`/`verify` also probe the Sheets host). A revoked/expired token fails its refresh here (gargle warns
   "Unable to refresh token" and deletes the file) → stops with the `auth`
   command to run. A network failure stops with "Could not reach Google" and
   leaves the login alone — do not re-run `auth` for that.
6. Prints `[gs_connect] Connected as <email> (<level>)`.

Helpers next to it in `gs_helpers.R`: `gs_config_path()`, `gs_config_email()`,
`gs_resolve_email()` (lower-cases), `gs_oauth_cache()`, `gs_cached_logins()` (data
frame of saved tokens: email, scopes, has_scope, file), `gs_live_check(token)`
(first live call; tells a dead token apart from a network problem).

## Where things live

| What | Path |
|---|---|
| Default account | `~/.config/r-googlesheets4/email` (`$XDG_CONFIG_HOME` honoured; `GS_CONFIG` overrides) |
| Token cache (macOS) | `~/Library/Caches/gargle/` |
| Token cache (Linux) | `~/.cache/gargle/` |
| Token file name | `<hash-of-client+scopes>_<email>` (an RDS of the gargle token; the dir and files are created private, mode 0700/0600) |

The cache is gargle's default, so it is **shared with RStudio**: a login made
by `gs_setup.sh` works in RStudio and vice-versa — provided the scopes match
(see next section). Tokens from the built-in tidyverse client refresh
themselves indefinitely until the user revokes access at
https://myaccount.google.com/permissions.

## Access levels (least privilege)

The default level requests only `spreadsheets`. Raise it only when the task needs
it, and only after the user agrees.

| `GS_SCOPE_LEVEL` | Scope(s) | Unlocks |
|---|---|---|
| `sheets` (default) | `spreadsheets` | create, read, write, format sheets |
| `readonly` | `spreadsheets.readonly` | read-only analysis |
| `export` | `spreadsheets` + `drive.readonly` | finding sheets by name (PDF export for visual QA works at the default level) |
| `drive` | `drive` | share, move, copy, delete files |

Google classes `drive` and `drive.readonly` as *restricted* scopes, which is why
they are opt-in. `gs_connect()` authenticates googledrive only at the `export` and
`drive` levels; helpers that need more stop with the exact command to run
(`gs_require_level()`).

gargle names each cached token file after a hash of the client, scopes and email,
so tokens for different levels sit side by side and never overwrite each other. A
login at another level is reported by `status` as `other-scopes`; `auth` signs in
again for the current level and leaves the other token alone.

To change level: `GS_SCOPE_LEVEL=export bash scripts/gs_setup.sh auth you@example.com`,
and set the same variable for the build script. The consent screen lists exactly
the scopes of that level and is the standard Tidyverse app (gargle's built-in OAuth
client), so no Google Cloud project is needed.

## The shared OAuth client: advantages and limits

googlesheets4 and gargle ship a shared OAuth client ("Tidyverse API Packages").
Per the tidyverse privacy policy that project never receives your data or the
permission to access it.

- **Advantage:** zero setup, one click, no Google Cloud project or consent-screen work.
- **Limits:** quota is shared with every other user of that client; the consent
  screen is not yours; whether Google lets that client serve a given restricted
  scope is outside this skill's control.
- **For heavy, team or unattended use:** register your own OAuth client
  (`gs4_auth_configure(path = "client.json")`, then re-run `auth`) or use a service
  account (`GS_SA_JSON`, and share the sheet with the service account's email).

See gargle's [get-api-credentials](https://gargle.r-lib.org/articles/get-api-credentials.html)
and [non-interactive auth](https://gargle.r-lib.org/articles/non-interactive-auth.html) articles.

## Switching or using several accounts

- Default account: whatever `auth` saved last (`~/.config/r-googlesheets4/email`).
- Per script: `gs_connect("work@example.com")`. If that account has no saved
  login, run `gs_setup.sh auth work@example.com` once — the default is
  unchanged.
- To change the default: `gs_setup.sh auth new@example.com`.
- To forget an account: delete its file from the token cache (and revoke at
  the Google permissions page if desired).

## Service account (cron, CI, servers without a browser)

```r
# Option 1 — via gs_connect(): set the env var, keep the script unchanged
Sys.setenv(GS_SA_JSON = "/secure/path/service-account.json")
gs_connect()

# Option 2 — direct
gs4_auth(path = "/secure/path/service-account.json",
         scopes = "https://www.googleapis.com/auth/drive")
drive_auth(token = gs4_token())

# Domain-wide delegation (act as a real user)
gs4_auth(path = "sa.json", subject = "user@example.com",
         scopes = "https://www.googleapis.com/auth/drive")
```

Service-account JSON is created in Google Cloud Console → IAM → Service
Accounts. The account must be added as an editor on each spreadsheet (or use
domain-wide delegation).

A **cron job on the same machine and OS user** does not need a service
account: the saved user token refreshes itself headlessly, so
`Rscript refresh.R` with `gs_connect()` just works.

## RStudio Server, Posit Cloud, remote/headless machines

The browser redirect targets `localhost`, so the sign-in must happen on the
machine running R **with** a browser. On a remote/hosted server either run
`gs_setup.sh auth` on a laptop and copy the token file into the server's cache
directory (same OS user, same path as above), or use a service account.

## Namespace pin (required)

`googlesheets4` and `googledrive` both export `request_generate()` and
`request_make()`. Last-loaded wins on the search path. After
`library(googledrive)`, calls to `request_generate("sheets.spreadsheets.batchUpdate", …)`
fail with **"Endpoint not recognized: 'sheets.spreadsheets.batchUpdate'"** because
Drive's endpoint registry doesn't know Sheets endpoints.

The fix is built into `scripts/gs_helpers.R` — it pins both functions to the
googlesheets4 versions:

```r
request_generate <- googlesheets4::request_generate
request_make     <- googlesheets4::request_make
```

If you load `googledrive` AFTER sourcing `gs_helpers.R`, you must re-pin —
the simpler rule: source `gs_helpers.R` last.

## Verifying the current user

```r
gs4_user()    # Sheets identity
drive_user()  # Drive identity (same, since the token is shared)
gs4_scopes()  # available scope short-names
gargle::gargle_oauth_sitrep()   # every token in the cache: email, client, scopes
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `gs_connect()`: "No Google account configured" | `gs_setup.sh auth you@example.com` |
| `gs_connect()`: "No saved Google login for <email> with the requested access" | `gs_setup.sh auth <email>` (also the fix for a `spreadsheets`-only token made in RStudio) |
| `gs_connect()`: "no longer works (revoked or expired)" | Token was revoked at Google or the refresh failed; gargle deleted it. `gs_setup.sh auth <email>` |
| `auth` → `reason=timeout` | Nobody clicked Allow within `GS_AUTH_TIMEOUT` s (300). Re-run and complete the browser step; nothing was saved. |
| `auth` → `reason=denied` | Cancel/Deny was clicked, or Google refused the code exchange. Re-run, click Allow. |
| `auth` → `reason=port` | Could not listen on a local port. Check firewalls/sandboxes that block loopback listeners. |
| `auth` → `reason=network` | Cannot reach Google. See the IPv4 quirk below; check proxy/VPN. |
| `BROWSER_NOT_OPENED` in the `auth` output, or no tab appeared although it says "Launched your browser" | No opener (`open`/`xdg-open`), no graphical session (SSH, headless Linux/WSL without `DISPLAY`), or `GS_NO_BROWSER` set. Paste the printed `https://accounts.google.com/…` link into a browser **on the same computer** (the redirect goes to `localhost`) while the command is still waiting — a link from an exited run is dead. |
| `status` reports unreadable token file(s) / `gs_connect()` mentions them | A corrupt file in the cache breaks every gargle cache load. `auth` moves such files to `<cache>-corrupt/` automatically; delete that folder when done. |
| `auth` → `reason=in-progress` / two Google tabs / "Port 1410 is busy" during a first sign-in | A second `auth` was started while the first was waiting. Finish the first tab; let the other time out; do not start a third. |
| `install` ends in `NEEDS_INSTALL` again | A package failed to build. Linux: `libcurl4-openssl-dev libssl-dev` (Debian/Ubuntu) or `libcurl-devel openssl-devel` (Fedora/RHEL). No writable library: `GS_LIB=~/R/library`. Then re-run `install`. |
| `gs_connect()`: "Could not reach Google to verify the saved login" | Network problem, not an auth problem — the login is intact. Check VPN/proxy; see the IPv4 quirk below. Do not re-run `auth`. |
| `READY` but `reason=mismatch` | The user picked another Google account in the browser; that one was saved. Re-run `auth <wanted-email>` and pick the right account. |
| "Google hasn't verified this app" | Should not appear with the built-in tidyverse client. If it does, click *Advanced → Go to tidyverse*; it is the standard app used by googlesheets4. |
| "Insufficient permission" (403) on Drive calls | The token lacks the Drive scope the task needs. Ask the user, then `GS_SCOPE_LEVEL=drive bash scripts/gs_setup.sh auth <email>` (or `export` for read-only Drive access). |
| Works interactively, breaks when sourced | Namespace pin — see above. |
| `gs4_auth()` opens a browser every run (RStudio) | Caching is off there — `gargle::gargle_oauth_cache()`; the skill always passes an explicit cache path. |

## Network quirk: `Could not resolve host: sheets.googleapis.com`

If Drive calls succeed but Sheets calls fail with a resolve error (or vice
versa — it's per-host), the system resolver is likely returning IPv6-only
answers on a network with no IPv6 route. `dig +short <host>` works while
`curl` fails; `dscacheutil -q host -a name <host>` (macOS) shows only
`ipv6_address` rows. Fix once, before auth:

```r
httr::set_config(httr::config(ipresolve = 1L))   # force IPv4 for all httr/gargle calls
```

All of googlesheets4 / googledrive / gargle route through httr, so this one
line covers every API call in the session.
