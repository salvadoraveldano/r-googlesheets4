# No R? Your options

This skill is built on R. It never installs R for you. Choose one path.

## A. Install R yourself (about 5 minutes)

| Platform | Option |
|---|---|
| Any | CRAN installer: <https://cloud.r-project.org> |
| Any | [rig](https://github.com/r-lib/rig), a version manager from the r-lib team (`rig add release`) |
| macOS | Homebrew: `brew install --cask r` |
| Linux | Posit's builds: <https://docs.posit.co/resources/install-r.html> |

Then re-run `bash scripts/gs_setup.sh status`. The skill will ask before it
installs the CRAN packages it needs (googlesheets4, googledrive, gargle, plus httpuv for the sign-in).

## B. Skip R

Everything below is a third-party project. Read its README, check its license,
and pin a version instead of `@latest` (an unpinned install is a supply-chain risk).
The skill's formatting helpers and the visual QA loop do not carry over.

| Tool | What it is | Auth |
|---|---|---|
| [gspread](https://docs.gspread.org) | Python client for the Sheets API | Service account or OAuth ([docs](https://docs.gspread.org/en/latest/oauth2.html)). The key files are sensitive; keep them out of git. |
| Sheets MCP servers (for example `mcp-google-sheets`, `mcp-gsheets`) | Lets an agent read and write sheets through MCP tools | Service account, OAuth or application default credentials, per each server's README |

## Why R is still worth it for this job

- **Zero Google Cloud setup.** googlesheets4 and gargle ship a shared OAuth client, so signing in takes one click. Python routes and most self-hosted MCP servers need you to create a Google Cloud project or a service account first.
- **Tidyverse data flow.** Data frames go straight to styled sheets.
- **The helpers in this skill**: batchUpdate wrappers, charts, banded ranges, conditional formats and the PDF review loop.

Where the shared client falls short: its quota is shared with every other user of
that client, and its consent screen is not yours. For heavy, team or unattended
use, point `GS_OAUTH_CLIENT` at your own OAuth client JSON, or use a service
account (`GS_SA_JSON`). Steps: [auth.md](auth.md#your-own-oauth-client-gs_oauth_client).
