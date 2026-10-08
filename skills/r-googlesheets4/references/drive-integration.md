# googledrive Integration

> **Access level:** everything on this page uses googledrive and needs `GS_SCOPE_LEVEL=drive` (finding files by name needs at least `export`). Ask the user before raising the level; see [setup-protocol.md](setup-protocol.md). `gs_require_level()` stops with the exact command.

`googlesheets4` handles cell content and formatting. **File-level
operations** — moving sheets between folders, sharing, copying,
renaming, uploading XLSX → convert to Sheets — go through `googledrive`.

```r
library(googledrive)
```

## Find sheets

```r
drive_find("Budget", type = "spreadsheet")
# tibble of matches; each row's $id is the spreadsheet ID
```

## Move to a folder

```r
folder <- drive_get("Finance/FY2026")
drive_mv(ss, path = folder)
```

## Rename

```r
drive_rename(ss, name = "FY2026 Budget — FINAL")
```

## Copy

```r
drive_cp(ss, name = "FY2026 Budget — Backup")
```

## Trash / delete

```r
drive_trash(ss)   # moves to trash (recoverable for 30 days)
drive_rm(ss)      # permanent
```

## Sharing & permissions

```r
# Share with a specific user
drive_share(ss, role = "writer", type = "user",
            emailAddress = "viewer@example.com")

drive_share(ss, role = "reader", type = "user",
            emailAddress = "viewer2@example.com")

# Share with everyone in a domain
drive_share(ss, role = "reader", type = "domain",
            domain = "example.com")

# Make link-shareable (anyone with the URL can view)
drive_share(ss, role = "reader", type = "anyone")

# Remove access — NOTE: drive_share_delete() does NOT exist in googledrive
# (verified absent in 2.1.2). Revoke via the raw Permissions API:
perms <- drive_reveal(ss, "permissions")$permissions_resource[[1]]$permissions
perm_id <- vapply(perms, `[[`, "", "id")[
  vapply(perms, function(z) identical(z$emailAddress, "former-user@example.com"), TRUE)]
req <- googledrive::request_generate(          # explicit namespace — see pin note
  endpoint = "drive.permissions.delete",
  params   = list(fileId = as.character(as_id(ss)), permissionId = perm_id))
googledrive::request_make(req)                 # HTTP 204 = revoked
```

`role` ∈ `owner` / `organizer` / `fileOrganizer` / `writer` / `commenter`
/ `reader`.

### What a shared sheet exposes

Tell the user these before sharing, and ask which role and audience they want:

- **Anyone with the link sees who owns the file.** The owner's name goes out with the
  link, so a link-shared sheet is not anonymous. Version history and "last edit"
  details are normally limited to editors, but this is Google's behavior and not
  checked here: have the user open the link in a private window and look before they post it.
- **A posted link is public.** Anyone who gets it can open the sheet, pass it on, or
  index it. Changing the sharing later stops new visits; it does not recall copies
  people already made.
- **Protected ranges store the account that created them as an editor.** Checked
  live: a default `fmt_protected_range()` listed the owner as its one editor. The
  Sheets API shows the editors list to editors only, but the owner's account is
  part of the file.
- **View-only visitors cannot use dropdowns or pickers.** Input cells look dead to
  them. Tell them to use File > Make a copy and work in their own copy. Use the
  `writer` role only if they must edit the original.
- Share the narrowest set: `role = "reader"`, only the sheets named, only the people or
  link scope the user confirmed. Never share on your own initiative.

## Upload XLSX → convert to Sheets

```r
drive_upload(
  "output/Summary_FY2026.xlsx",
  name = "Summary FY2026",
  type = "spreadsheet"   # auto-converts to Google Sheets
)
```

Without `type = "spreadsheet"`, Drive stores the file as `.xlsx` in its
native format, accessible only via Sheets' "Open in Sheets" path.

## Permissions: getting the current state

```r
perms <- drive_reveal(ss, "permissions")
# returns a list-column with all current permissions
```

## Working with shared drives

For Team Drives / Shared Drives, pass the team drive ID:

```r
team_drive <- shared_drive_get("FY2026")
ss <- gs4_create("Budget", folder = as_id(team_drive$id))
```
