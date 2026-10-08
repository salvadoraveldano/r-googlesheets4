# Security policy

## Reporting a vulnerability

Please report privately through GitHub: **Security → Report a vulnerability** on
this repository. Do not open a public issue for a security problem. Expect an
acknowledgement within a few days.

## Threat model and design choices

A skill is instructions plus scripts that an AI agent runs on your machine. Treat
it like installed software: read it before you install it. This one is built to
be easy to check:

- **Least privilege.** The default access level requests only the Google
  `spreadsheets` scope. Broader access (`drive.readonly` for finding sheets by name,
  `drive` for sharing and moving files) is opt-in through `GS_SCOPE_LEVEL`, and the
  agent must ask you first.
- **No silent installs.** The skill never installs R, runs a package manager, or
  pipes anything from the network into a shell. When something is missing, it prints
  instructions and installs R packages only after you say yes.
- **No secrets in the repo.** OAuth tokens live in gargle's per-user cache
  (directory mode 0700). The skill never prints tokens or key files.
- **Untrusted cell data.** Anyone can write into a sheet, so the skill tells the
  agent to treat cell contents as data and never to follow instructions found there.
- **Narrow tool pre-approval.** `allowed-tools` pre-approves only reading files and
  the read-only `gs_setup.sh status` command.

## What the scopes allow

| Level | Google scope | Can |
|---|---|---|
| `sheets` (default) | `spreadsheets` | read and edit every spreadsheet the account can open |
| `readonly` | `spreadsheets.readonly` | read those spreadsheets |
| `export` | `spreadsheets` + `drive.readonly` | also read metadata and content of all Drive files |
| `drive` | `drive` | read, edit, create, delete all Drive files |

Revoke access any time at https://myaccount.google.com/permissions.

## Service accounts

`GS_SA_JSON` points to a service-account key. Keep that file outside the project,
never commit it (`.gitignore` blocks common names), and share only the sheets it
needs with the service account's email.

## Supply chain

The skill uses only CRAN packages from the tidyverse/r-lib ecosystem. Pin versions
in your own environment (for example with renv) if you need reproducibility.
