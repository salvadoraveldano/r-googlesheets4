# Authentication & Scopes

How the skill connects to Google — and what to do when it doesn't.

## The short version

- **One-time setup** (per computer, per Google account). Opens the Google
  sign-in page, waits for **Allow**, verifies the Sheets API, and saves the
  account as the default when none is saved yet:

  ```bash
  bash scripts/gs_setup.sh auth you@example.com
  ```

- **Every script** starts with:

  ```r
  SKILL <- Sys.getenv("GS_SKILL_DIR", "/abs/path/to/the/skill")
  source(file.path(SKILL, "scripts", "gs_helpers.R"))
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
sheets.googleapis.com), and saves the account as the default when none is saved
yet (or no email was given). Build scripts must never try to
authenticate on their own. The sign-in only accepts the browser flow: other
credentials on the machine (`GOOGLE_APPLICATION_CREDENTIALS`, gcloud, a GCE VM)
are never used in its place.

## `gs_setup.sh` reference

| Command | What it does | Network |
|---|---|---|
| `status [email]` | Packages present? Which account? Is there a saved login at the current access level for it? Lists saved logins as `cached=…`. When given an email, READY, and no default saved yet, saves that email as the default. | no |
| `install` | `install.packages()` for the missing packages (CRAN binaries preferred). Run in the background — minutes. | yes |
| `auth [email]` | Google sign-in for that account (default: the saved one; silent if a valid login already exists), verify. Saves the account Google reports as the default only when no default exists yet or no email was given (so `auth other@x` leaves the default alone). Run in the background — waits for the click. Refuses to start while another `auth` is waiting (`reason=in-progress`). | yes |
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
| `AUTH_FAILED` | 6 | `reason=timeout` / `denied` / `other` → re-run `auth` at most once. `in-progress` → finish the sign-in that is already waiting. `port` → a firewall/sandbox blocks the loopback listener. `network` → fix connectivity, then `verify`. `verify-failed` → Google accepted the sign-in but refuses the API call for this account. `service-account` (`next=fix-GS_SA_JSON`) → `GS_SA_JSON` is missing or not a usable key; fix the path/key, then `verify`. `oauth-client` (`next=fix-GS_OAUTH_CLIENT`) → `GS_OAUTH_CLIENT` is missing or not a client JSON; fix it, then re-run `status`. `api-disabled` → the login works, but the Sheets or Drive API is not enabled in the Cloud project of the OAuth client or service account; enable it, then `verify` (the login is kept). |
| `ERROR` | 1 | `reason=unknown-command` / `helpers-missing`. |

`reason=mismatch` on `READY` means the user picked a different Google account in
the browser than requested; that account's login is saved, but it is not made the
default. `cached=` is
printed by `status` only. Emails are lower-cased everywhere (that is how gargle
names its cache files).

Environment overrides. Each R process reads them when it starts, so set them for
**both** `gs_setup.sh` and every build or cron run (for example
`GS_SCOPE_LEVEL=drive Rscript build.R`), not in an R console:

| Variable | Effect |
|---|---|
| `GS_SCOPE_LEVEL` | Access level (see below). Default `sheets`. |
| `GS_EMAIL` | Account to use when none is given (`gs_connect()` and `gs_setup.sh`). `GS_EMAIL=x gs_setup.sh auth` also makes `x` the default. |
| `GS_CONFIG` | Path of the file holding the default account. |
| `GS_OAUTH_CACHE` | Token cache directory (absolute path). The `gargle_oauth_cache` R option is ignored. |
| `GS_OAUTH_CLIENT` | Your own OAuth client JSON instead of the shared tidyverse one (see below). |
| `GS_SA_JSON` | Service-account key → `gs_connect()` uses it instead of a user login. |
| `GS_AUTH_TIMEOUT` | Seconds to wait for the browser sign-in (default 300). |
| `GS_NO_BROWSER=1` | Never launch a browser (link is still printed). |
| `GS_IPV4=1` | Force IPv4 for every Google call (see "Network quirk"). |

`GOOGLE_APPLICATION_CREDENTIALS` and gcloud's default credentials are **ignored**:
the skill only uses the saved user login or `GS_SA_JSON`, so a service-account key
set for other tools (BigQuery, GCS) never stands in for you.

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
   `GS_SCOPE_LEVEL`** (and, when `GS_OAUTH_CLIENT` is set, made with that client).
   None → stops: *"No saved Google login for <email> with the
   requested access (sheets). Run once: … auth <email>"*. It never guesses from other cached accounts and
   never opens a browser.
4. Loads the newest such token file and hands it to `gs4_auth(token = )`. Only
   that token is used: no gargle cache lookup by hash, no other credential source.
   At the `export` and `drive` levels the same token also authenticates googledrive.
5. The token refreshes, then one live call (`gs4_user()` at the Sheets levels, `drive_user()` at the Drive
   levels; `auth`/`verify` also probe the Sheets host). A revoked/expired token fails its refresh here (gargle
   deletes the file) → stops with the `auth`
   command to run. A network failure stops with "Could not reach Google" and
   leaves the login alone — do not re-run `auth` for that.
6. Prints `[gs_connect] Connected as <email> (<level>)`, using the account Google reports.

Helpers next to it in `gs_helpers.R`: `gs_config_path()`, `gs_config_email()`,
`gs_resolve_email()` (lower-cases), `gs_oauth_cache()`, `gs_cached_logins()` (data
frame of saved tokens: email, scopes, has_scope, client, client_ok, mtime, file), `gs_live_check(token)`
(first live call; tells a dead token apart from a network problem).

## Where things live

| What | Path |
|---|---|
| Default account | `~/.config/r-googlesheets4/email` (`$XDG_CONFIG_HOME` honoured; `GS_CONFIG` overrides) |
| Token cache (macOS) | `~/Library/Caches/gargle/` |
| Token cache (Linux) | `~/.cache/gargle/` |
| Token file name | `<hash-of-client+scopes>_<email>` (an RDS of the gargle token; the dir and files are created private, mode 0700/0600) |

The cache is gargle's default, so it is **shared with RStudio** on the same
machine: a login made by `gs_setup.sh` works in RStudio and vice-versa, provided
the scopes match (see next section). `gs_connect()` also accepts a token that
RStudio Server or another OAuth client made, because it loads the file directly
(unless `GS_OAUTH_CLIENT` is set: then only that client's tokens count).
Tokens from the built-in tidyverse client refresh themselves indefinitely until
the user revokes access at https://myaccount.google.com/permissions.

The skill does not read gargle's `gargle_oauth_cache` option. To keep tokens in a
project folder, set `GS_OAUTH_CACHE` to its **absolute** path for setup and builds.

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
and set the same variable for every run of the build script
(`GS_SCOPE_LEVEL=export Rscript build.R`, or `Sys.setenv(GS_SCOPE_LEVEL = "export")`
**before** `source("gs_helpers.R")`, which reads it once). The consent screen lists exactly
the scopes of that level. It is the standard Tidyverse app (gargle's built-in OAuth
client), so no Google Cloud project is needed, unless you set `GS_OAUTH_CLIENT`.

## The shared OAuth client: advantages and limits

googlesheets4 and gargle ship a shared OAuth client ("Tidyverse API Packages").
Per the tidyverse privacy policy that project never receives your data or the
permission to access it.

- **Advantage:** zero setup, one click, no Google Cloud project or consent-screen work.
- **Limits:** quota is shared with every other user of that client; the consent
  screen is not yours; whether Google lets that client serve a given restricted
  scope is outside this skill's control.
- **For heavy, team or unattended use:** use your own OAuth client (next
  section) or a service account (`GS_SA_JSON`, and share the sheet with the
  service account's email).

See gargle's [get-api-credentials](https://gargle.r-lib.org/articles/get-api-credentials.html)
and [non-interactive auth](https://gargle.r-lib.org/articles/non-interactive-auth.html) articles.

## Your own OAuth client (`GS_OAUTH_CLIENT`)

Your own Google Cloud project gives you your own quota and a consent screen with
your name on it. One-time setup in the [Google Cloud console](https://console.cloud.google.com/):

1. Create a project, then enable the **Google Sheets API** (and the **Google
   Drive API** for the `export` and `drive` levels).
2. Configure the OAuth consent screen. While the app is in "Testing", add each
   Google account that will sign in as a test user.
3. Create an OAuth client ID of type **Desktop app** and download its JSON. Keep
   it outside any git repository: it holds the client secret.
4. Point both the sign-in and every build at it (an env var, because
   `gs4_auth_configure()` in a console only lasts for that R session):

```bash
export GS_OAUTH_CLIENT=/abs/path/client.json   # the file you downloaded
bash scripts/gs_setup.sh auth you@example.com   # one new sign-in with your client
Rscript build.R                                  # gs_connect() now uses that login
```

Logins made with the shared client are not reused while `GS_OAUTH_CLIENT` is set
(`status` lists them as `other-client`), so expect one new sign-in. `status`
prints which sign-in app is in use. To go back to the shared client, unset the variable **and** delete
that client's token file from the cache (`gargle::gargle_oauth_sitrep()` shows each file's client):
otherwise `gs_connect()` keeps using the newest saved login, which is that one.

## Switching or using several accounts

- Default account: the one in `~/.config/r-googlesheets4/email`. `auth` writes it
  only when none exists yet or when no email was given on the command line.
- Per script: `gs_connect("work@example.com")`. If that account has no saved
  login, run `gs_setup.sh auth work@example.com` once. The default is
  unchanged.
- To change the default: `GS_EMAIL=new@example.com bash scripts/gs_setup.sh auth`
  (or edit the file).
- To forget an account: delete its file from the token cache (and revoke at
  the Google permissions page if desired).

## Service account (cron, CI, servers without a browser)

Set the env var and keep the script unchanged; `gs_connect()` picks it up:

```bash
GS_SA_JSON=/secure/path/service-account.json Rscript build.R
```

Service-account JSON is created in Google Cloud Console → IAM → Service
Accounts. The account must be added as an editor on each spreadsheet. Domain-wide
delegation (acting as a user) is not supported by `gs_connect()`.

A **cron job on the same machine and OS user** does not need a service
account: the saved user token refreshes itself headlessly, so
`Rscript refresh.R` with `gs_connect()` just works. Put any non-default settings
in the cron line too (`GS_SCOPE_LEVEL=drive SHEET_ID=… Rscript refresh.R`): cron
does not see variables from your shell.

## RStudio Server, Posit Cloud, remote/headless machines

The browser redirect targets `localhost`, so the sign-in must happen on the
machine running R **with** a browser. On a remote/hosted server either run
`gs_setup.sh auth` on a laptop and copy the token file into the server's cache
directory (same OS user, same path as above) together with
`~/.config/r-googlesheets4/email` (or set `GS_EMAIL`), or use a service account.

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
| `status` reports unreadable token file(s) | A corrupt file in the cache breaks a new browser sign-in (gargle's loader reads every file). `gs_connect()` is not affected. `auth` moves such files to `<cache>-corrupt/` when it signs in; delete that folder when done. |
| `gs_connect()`: "a Google API is not enabled" / `auth` → `reason=api-disabled` | Usually with `GS_OAUTH_CLIENT` or a new service account: enable the Google Sheets API (and Drive API for export/drive) in that Cloud project. Do not sign in again. |
| `auth` → `reason=in-progress` / two Google tabs / "Port 1410 is busy" during a first sign-in | A second `auth` was started while the first was waiting. Finish the first tab; let the other time out; do not start a third. |
| `install` ends in `NEEDS_INSTALL` again | A package failed to build. Linux: `libcurl4-openssl-dev libssl-dev` (Debian/Ubuntu) or `libcurl-devel openssl-devel` (Fedora/RHEL). No writable library: create `~/R/library`, add `R_LIBS_USER=~/R/library` to `~/.Renviron` yourself (every R process reads it, including cron and build runs). Then re-run `install`. |
| `gs_connect()`: "Could not reach Google to verify the saved login" | Network problem, not an auth problem — the login is intact. Check VPN/proxy; see the IPv4 quirk below. Do not re-run `auth`. |
| `READY` but `reason=mismatch` | The user picked another Google account in the browser; its login was saved, the default was not changed. Re-run `auth <wanted-email>` and pick the right account. |
| `gs_connect()` connects as an unexpected account | Check `GS_EMAIL` and the default-account file. A key in `GOOGLE_APPLICATION_CREDENTIALS` is never used. |
| "Google hasn't verified this app" | Should not appear with the built-in tidyverse client. If it does, click *Advanced → Go to tidyverse*; it is the standard app used by googlesheets4. |
| "Insufficient permission" (403) on Drive calls | The token lacks the Drive scope the task needs. Ask the user, then `GS_SCOPE_LEVEL=drive bash scripts/gs_setup.sh auth <email>` (or `export` for read-only Drive access). |
| Works interactively, breaks when sourced | Namespace pin — see above. |
| `gs4_auth()` opens a browser every run (RStudio) | Caching is off there — `gargle::gargle_oauth_cache()`; the skill always passes an explicit cache path. |

## Network quirk: `Could not resolve host: sheets.googleapis.com`

If Drive calls succeed but Sheets calls fail with a resolve error (or vice
versa — it's per-host), the system resolver is likely returning IPv6-only
answers on a network with no IPv6 route. `dig +short <host>` works while
`curl` fails; `dscacheutil -q host -a name <host>` (macOS) shows only
`ipv6_address` rows. Fix: set `GS_IPV4=1` for the setup command and every build
run (an R console setting would not reach them, because each starts its own R):

```bash
GS_IPV4=1 bash scripts/gs_setup.sh auth you@example.com
GS_IPV4=1 Rscript build.R
```

`gs_helpers.R` then runs `httr::set_config(httr::config(ipresolve = 1L))`. All of
googlesheets4 / googledrive / gargle route through httr, so this covers every API call.
