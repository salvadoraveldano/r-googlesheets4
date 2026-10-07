# =============================================================================
# gs_setup.R — one-time Google connection setup for the r-googlesheets4 skill
# =============================================================================
#
# Always run through the wrapper (it finds Rscript):
#   bash scripts/gs_setup.sh <command> [email]
#
#   status  [email]   Offline check (< 3 s): packages present? which account is
#                     configured? is there a saved Google login for it?
#   install           Install the missing R packages from CRAN (minutes).
#   auth    [email]   Sign in to Google for that account (default: the saved
#                     one). Opens the consent page in the browser, waits for
#                     "Allow", verifies, saves the account as the default.
#                     Silent (no browser) if a valid login already exists.
#   verify  [email]   Live check that gs_connect() works for the account.
#
# The LAST line of stdout is machine-readable so an agent can branch on it:
#   GS_SETUP state=<STATE> email=<x|-> reason=<..|-> next=<command|-> [cached=...]
# States / exit codes:
#   READY, INSTALLED = 0   NEEDS_R = 2   NEEDS_INSTALL = 3   NEEDS_EMAIL = 4
#   NEEDS_AUTH = 5         AUTH_FAILED = 6   ERROR = 1
#
# Why this script exists: Claude Code runs R non-interactively (Rscript), and
# gargle refuses to start the browser OAuth flow in a non-interactive session.
# `auth` flips gargle's interactivity switch (options(rlang_interactive=TRUE)),
# opens the consent URL itself (httr only *prints* it under Rscript), passes an
# explicit cache path (otherwise gargle asks a console question that can never
# be answered here), and puts a timeout on the wait.
#
# Env overrides (mainly for tests and unusual setups):
#   GS_OAUTH_CACHE   token cache dir (default: gargle's OS default)
#   GS_CONFIG        path of the file that remembers the default account
#   GS_EMAIL         account to use when none is given on the command line
#   GS_LIB           R library to install packages into
#   GS_AUTH_TIMEOUT  seconds to wait for the browser sign-in (default 300)
#   GS_NO_BROWSER=1  never launch a browser (link is still printed)
#   GS_SCOPE_LEVEL   sheets (default) | readonly | export | drive — see gs_helpers.R
# =============================================================================

PKGS     <- c("googlesheets4", "googledrive", "gargle", "httr", "httpuv", "glue")

# ── Locate the skill's scripts dir (works when run from anywhere) ----------
.script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
SCRIPTS_DIR <- if (length(.script_file) && nzchar(.script_file[1])) {
  normalizePath(dirname(.script_file[1]))
} else {
  file.path(getwd(), "scripts")
}

# Plain-language description of the current scope level, for the consent screen note
scope_plain <- function() switch(GS_SCOPE_LEVEL,
  sheets   = "read and edit your Google Sheets",
  readonly = "read your Google Sheets",
  export   = "edit Sheets and read-only access to Drive for PDF export",
  drive    = "full access to your Google Drive")

SETUP_SH <- paste("bash", shQuote(file.path(SCRIPTS_DIR, "gs_setup.sh")))

# ── Output helpers -----------------------------------------------------------
say <- function(...) cat("[gs_setup] ", ..., "\n", sep = "")

EXIT_CODES <- c(READY = 0L, INSTALLED = 0L, NEEDS_R = 2L, NEEDS_INSTALL = 3L,
                NEEDS_EMAIL = 4L, NEEDS_AUTH = 5L, AUTH_FAILED = 6L, ERROR = 1L)

#' Print the machine-readable summary line and exit.
emit <- function(state, email = "-", reason = "-", next_cmd = "-", cached = NULL) {
  q <- function(x) if (grepl("[[:space:]]", x)) sprintf('"%s"', x) else x
  line <- sprintf("GS_SETUP state=%s email=%s reason=%s next=%s",
                  state, q(email), q(reason), q(next_cmd))
  if (!is.null(cached)) line <- paste0(line, " cached=", cached)
  cat(line, "\n", sep = "")
  quit(save = "no", status = EXIT_CODES[[state]])
}

missing_pkgs <- function() {
  PKGS[!vapply(PKGS, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
}

require_pkgs_or_exit <- function() {
  miss <- missing_pkgs()
  if (length(miss)) {
    say("Missing R packages: ", paste(miss, collapse = ", "))
    emit("NEEDS_INSTALL", reason = paste(miss, collapse = ","), next_cmd = "install")
  }
}

load_helpers <- function() {
  f <- file.path(SCRIPTS_DIR, "gs_helpers.R")
  if (!file.exists(f)) { say("Cannot find ", f); emit("ERROR", reason = "helpers-missing") }
  source(f, local = FALSE)
}

#' Launch the default browser. Returns the opener used ("open", "xdg-open") or "".
open_browser <- function(url) {
  if (nzchar(Sys.getenv("GS_NO_BROWSER"))) return("")
  os <- Sys.info()[["sysname"]]
  if (identical(os, "Darwin")) {
    # `open` returns as soon as LaunchServices takes the URL (ms) and exits
    # non-zero when there is no GUI session / URL handler (e.g. over SSH).
    rc <- tryCatch(system2("open", shQuote(url), stdout = FALSE, stderr = FALSE, wait = TRUE),
                   error = function(e) 1L)
    return(if (identical(as.integer(rc), 0L)) "open" else "")
  }
  # Linux: xdg-open may block while the browser runs, so keep it asynchronous
  # (its exit status is then meaningless) and detect headless sessions up front.
  if (!nzchar(Sys.which("xdg-open"))) return("")
  if (!nzchar(Sys.getenv("DISPLAY")) && !nzchar(Sys.getenv("WAYLAND_DISPLAY"))) return("")
  tryCatch({ system2("xdg-open", shQuote(url), stdout = FALSE, stderr = FALSE, wait = FALSE); "xdg-open" },
           error = function(e) "")
}

# "ok" = the login has exactly the scopes of the current GS_SCOPE_LEVEL
scope_label <- function(logins) ifelse(logins$has_scope, GS_SCOPE_LEVEL, "other-scopes")

cached_summary <- function(logins) {
  if (!nrow(logins)) return("-")
  paste(sprintf("%s(%s)", logins$email, scope_label(logins)), collapse = ",")
}

valid_email <- function(x) {
  !is.null(x) && length(x) == 1 && !is.na(x) &&
    grepl("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", x)
}

#' Resolve + validate the account or exit with NEEDS_EMAIL.
resolve_email_or_exit <- function(email_arg, cached = NULL) {
  email <- gs_resolve_email(email_arg)   # lower-cased, trimmed
  if (is.null(email)) {
    say("No Google account given or configured yet (", gs_config_path(), " is absent).")
    emit("NEEDS_EMAIL", next_cmd = "auth <email>", cached = cached)
  }
  if (!valid_email(email)) {
    say("'", email, "' is not a valid email address (expected something like you@example.com).")
    emit("NEEDS_EMAIL", email = email, reason = "invalid-or-missing-email",
         next_cmd = "auth <email>", cached = cached)
  }
  email
}

# ── status -------------------------------------------------------------------
cmd_status <- function(email_arg = NULL) {
  say("R ", as.character(getRversion()), " at ", R.home())
  require_pkgs_or_exit()
  say("R packages: all present (", paste(PKGS, collapse = ", "), ")")
  load_helpers()

  sa <- Sys.getenv("GS_SA_JSON", "")
  if (nzchar(sa)) {
    say("Service account configured via GS_SA_JSON=", sa)
    if (!file.exists(path.expand(sa))) {
      say("That file does not exist.")
      emit("AUTH_FAILED", reason = "service-account", next_cmd = "fix-GS_SA_JSON")
    }
    say("gs_connect() will use it (run `verify` for a live check).")
    emit("READY", email = "service-account")
  }

  cache  <- gs_oauth_cache()
  logins <- gs_cached_logins(cache)
  say("Token cache: ", cache, if (dir.exists(cache)) "" else " (not created yet)")
  say("Saved Google logins: ", if (nrow(logins)) cached_summary(logins) else "none")
  bad <- attr(logins, "unreadable")
  if (length(bad)) {
    say("Unreadable token file(s) in the cache (they break every sign-in until moved aside; ",
        "`auth` does that automatically): ", paste(basename(bad), collapse = ", "))
  }

  email <- resolve_email_or_exit(email_arg, cached = cached_summary(logins))
  say("Account: ", email)

  if (gs_has_login(logins, email)) {
    say("Ready — a saved login with ", GS_SCOPE_LEVEL, " access exists for ", email, ".")
    if (!is.null(email_arg) && is.null(gs_config_email())) {
      gs_save_config_email(email)
      say("Saved ", email, " as the default account (", gs_config_path(), ").")
    }
    emit("READY", email = email, cached = cached_summary(logins))
  }
  reason <- if (any(tolower(logins$email) == email)) "token-lacks-scope" else "no-saved-login"
  say("A one-time Google sign-in is needed for ", email, " (", reason, ").")
  emit("NEEDS_AUTH", email = email, reason = reason,
       next_cmd = paste("auth", email), cached = cached_summary(logins))
}

# ── install ------------------------------------------------------------------
cmd_install <- function() {
  miss <- missing_pkgs()
  if (!length(miss)) {
    say("All R packages already installed.")
    emit("INSTALLED", reason = "already-installed")
  }
  options(repos = c(CRAN = "https://cloud.r-project.org"),
          install.packages.compile.from.source = "never")   # prefer CRAN binaries

  lib <- Sys.getenv("GS_LIB", "")
  if (!nzchar(lib)) {
    writable <- .libPaths()[file.access(.libPaths(), 2) == 0]
    lib <- if (length(writable)) writable[1] else Sys.getenv("R_LIBS_USER")
  }
  lib <- path.expand(lib)
  if (!dir.exists(lib)) dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(lib, .libPaths()))

  say("Installing ", paste(miss, collapse = ", "), " into ", lib,
      " — this can take a few minutes, nothing to do on your side.")
  tryCatch(utils::install.packages(miss, lib = lib),
           error = function(e) say("install.packages error: ", conditionMessage(e)))

  still <- missing_pkgs()
  if (length(still)) {
    say("Still missing after install: ", paste(still, collapse = ", "),
        " — a package failed to build or install. Do not simply re-run install.")
    if (!identical(Sys.info()[["sysname"]], "Darwin")) {
      say("On Linux these need system libraries: libcurl4-openssl-dev libssl-dev ",
          "(Debian/Ubuntu) or libcurl-devel openssl-devel (Fedora/RHEL).")
    }
    say("If the library is not writable, set GS_LIB=~/R/library and re-run install.")
    emit("NEEDS_INSTALL", reason = paste(still, collapse = ","), next_cmd = "fix-system-deps")
  }
  say("R packages installed.")
  emit("INSTALLED")
}

# ── auth ---------------------------------------------------------------------
explain_signin <- function(email) {
  cat("\n",
      "==========================================================================\n",
      " Google sign-in for: ", email, "\n",
      "--------------------------------------------------------------------------\n",
      " Opening the Google sign-in page in your browser.\n",
      "   1. Pick the account ", email, "\n",
      "   2. Click 'Allow' (access level: ", GS_SCOPE_LEVEL, " — ", scope_plain(), ")\n",
      "      for the standard Tidyverse app, no Google Cloud setup needed)\n",
      "   3. When the tab says 'Authentication complete', come back here.\n",
      " This login is saved on this computer, so it only happens once.\n",
      "==========================================================================\n",
      sep = "")
}

#' Map a raw error to (reason, plain-language message).
classify_auth_error <- function(msg, timed_out = FALSE, timeout = NA) {
  if (timed_out || grepl("gs_setup timeout|elapsed time limit", msg)) {
    return(list(reason = "timeout",
                text = sprintf("Timed out after %s s waiting for the sign-in in the browser. Nothing was saved.", round(timeout))))
  }
  if (grepl("Failed to create server|address already in use|EADDRINUSE", msg, ignore.case = TRUE))
    return(list(reason = "port", text = paste0("Could not open the local port for the sign-in redirect (", msg, ").")))
  if (grepl("Authentication failed|access token|access_denied|invalid_grant|denied", msg, ignore.case = TRUE))
    return(list(reason = "denied", text = paste0("Google reported the sign-in was cancelled or denied (", msg, ").")))
  if (grepl("resolve host|Could not connect|Connection timed out|SSL|curl|Timeout was reached", msg, ignore.case = TRUE))
    return(list(reason = "network", text = paste0("Could not reach Google — network/DNS problem (", msg, ").")))
  list(reason = "other", text = msg)
}

pid_alive <- function(pid) {
  !is.na(pid) && isTRUE(tryCatch(tools::pskill(pid, 0L), error = function(e) FALSE))
}

#' Run the browser OAuth flow (or a silent cache hit) and install the token in
#' googlesheets4. Returns list(ok = TRUE) or list(ok = FALSE, reason, text).
#'
#' gs4_auth()'s token_fetch() swallows the real error and only says "Can't get
#' Google credentials" — but it reports the swallowed error as gargle *debug*
#' messages (a header "Error caught by token_fetch():" followed by the error
#' text as the NEXT message), so we turn debug verbosity on and capture it.
run_oauth <- function(email, cache) {
  # Private like gargle would make it: tokens are refresh credentials.
  dir.create(cache, recursive = TRUE, showWarnings = FALSE, mode = "0700")
  old_umask <- Sys.umask("077")
  on.exit(Sys.umask(old_umask), add = TRUE)

  # gargle's cache loader readRDS()es every file in the dir; one corrupt file
  # would make this sign-in fail. Move such files out of the way.
  bad <- attr(gs_cached_logins(cache), "unreadable")
  if (length(bad)) {
    quarantine <- paste0(cache, "-corrupt")
    dir.create(quarantine, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    file.rename(bad, file.path(quarantine, basename(bad)))
    say("Moved ", length(bad), " unreadable token file(s) to ", quarantine, ": ",
        paste(basename(bad), collapse = ", "))
  }

  # Guard against two sign-ins waiting at once (each would open a Google tab).
  lock <- file.path(cache, ".gs_setup.auth.lock")
  if (file.exists(lock)) {
    info <- tryCatch(readLines(lock, warn = FALSE), error = function(e) character())
    pid  <- suppressWarnings(as.integer(info[1]))
    if (pid_alive(pid)) {
      return(list(ok = FALSE, reason = "in-progress",
                  text = paste0("Another sign-in (", info[2], ", pid ", pid,
                                ") is already waiting in the browser. Finish that tab instead of starting a new one.")))
    }
    unlink(lock)
  }
  writeLines(c(as.character(Sys.getpid()), email), lock)
  on.exit(unlink(lock), add = TRUE)

  # Port 1410 is httr's default redirect target; pick another one if it's taken.
  probe <- tryCatch({
    s <- httpuv::startServer("127.0.0.1", 1410L,
                             list(call = function(req) list(status = 200L, headers = list(), body = "")))
    httpuv::stopServer(s); TRUE
  }, error = function(e) FALSE)
  if (!probe) {
    port <- httpuv::randomPort()
    Sys.setenv(HTTR_PORT = port, HTTR_SERVER_PORT = port)
    say("Port 1410 is busy — using port ", port, " for the sign-in redirect.")
  }

  timeout <- suppressWarnings(as.numeric(Sys.getenv("GS_AUTH_TIMEOUT", "300")))
  if (is.na(timeout) || timeout <= 0) timeout <- 300

  # gargle refuses OAuth in a non-interactive session; rlang_interactive is the
  # switch. The explicit cache path avoids gargle's "OK to cache?" question.
  old <- options(rlang_interactive = TRUE, gargle_oauth_cache = cache,
                 gargle_verbosity = "debug")
  on.exit(options(old), add = TRUE)

  # Timeout: a `later` timer that throws inside httr's listener loop (which
  # polls later via httpuv::service()). Deterministic, unlike setTimeLimit(),
  # which proved flaky around httpuv/later and could halt the whole script.
  caught <- NULL; expect_err <- FALSE; box_shown <- FALSE; timed_out <- FALSE
  cancel_timer <- later::later(function() {
    timed_out <<- TRUE
    stop(sprintf("gs_setup timeout: nobody completed the sign-in within %s s", round(timeout)),
         call. = FALSE)
  }, delay = timeout)
  on.exit(cancel_timer(), add = TRUE)

  res <- tryCatch(
    withCallingHandlers(
      googlesheets4::gs4_auth(email = email, scopes = GS_SCOPE, cache = cache),
      message = function(m) {
        txt <- conditionMessage(m)
        # httr prints the consent URL instead of opening it (non-interactive R).
        url <- regmatches(txt, regexpr("https://accounts\\.google\\.com[^[:space:]]+", txt))
        if (length(url) && !box_shown) {
          box_shown <<- TRUE
          explain_signin(email)
          opener <- open_browser(url)
          if (nzchar(opener)) {
            say("Launched your browser (", opener, ") with the Google sign-in page. ",
                "If no tab appeared, open this link on THIS computer:")
          } else {
            say("BROWSER_NOT_OPENED — could not launch a browser automatically. ",
                "Open this link in a browser ON THIS COMPUTER:")
          }
          cat("\n", url, "\n\n", sep = "")
          say("Waiting for you to finish the sign-in in the browser (up to ",
              ceiling(timeout / 60), " min) ...")
        }
        if (grepl("caught by", txt)) {
          expect_err <<- TRUE             # the real error is the NEXT message
        } else if (expect_err) {
          caught <<- trimws(txt); expect_err <<- FALSE
        }
        invokeRestart("muffleMessage")    # hide gargle's debug chatter
      }
    ),
    error = function(e) e
  )
  cancel_timer()

  if (inherits(res, "error")) {
    msg <- if (!is.null(caught) && nzchar(caught)) caught else conditionMessage(res)
    return(c(list(ok = FALSE),
             classify_auth_error(msg, timed_out = timed_out, timeout = timeout)))
  }
  list(ok = TRUE)
}

cmd_auth <- function(email_arg = NULL) {
  require_pkgs_or_exit()
  load_helpers()
  email  <- resolve_email_or_exit(email_arg)
  cache  <- gs_oauth_cache()
  logins <- gs_cached_logins(cache)
  cached <- gs_has_login(logins, email)
  if (cached) say("A saved login for ", email, " already exists — checking it (no browser needed).")

  res <- run_oauth(email, cache)
  if (!isTRUE(res$ok)) {
    say("Sign-in did not complete: ", res$text)
    emit("AUTH_FAILED", email = email, reason = res$reason,
         next_cmd = if (identical(res$reason, "in-progress")) "wait" else paste("auth", email))
  }

  # Live verification of BOTH API hosts. A revoked cached token surfaces here.
  chk    <- gs_live_check(googlesheets4::gs4_token(), sheets = TRUE)
  actual <- tryCatch(suppressMessages(googlesheets4::gs4_user()), error = function(e) NA_character_)
  if (!chk$ok) {
    if (chk$auth_problem && cached) {
      # Never escalate a "silent" check into a browser flow the user was not
      # told about: remove the dead token (only that one) and
      # hand control back so the agent can explain the sign-in first.
      say("The saved login for ", email, " no longer works (", chk$message,
          "). Removed it — a new Google sign-in is needed.")
      unlink(logins$file[logins$email == email & logins$has_scope])
      googlesheets4::gs4_deauth(); googledrive::drive_deauth()
      emit("NEEDS_AUTH", email = email, reason = "token-revoked", next_cmd = paste("auth", email))
    }
    if (chk$auth_problem) {
      say("Google accepted the sign-in but refuses the API call for ", email, ": ", chk$message)
      emit("AUTH_FAILED", email = email, reason = "verify-failed", next_cmd = paste("auth", email))
    }
    cls <- classify_auth_error(chk$message)
    say("Could not verify the login for ", email, " (", cls$text,
        "). Nothing was removed — fix connectivity, then run `verify`.")
    emit("AUTH_FAILED", email = email, reason = if (cls$reason == "other") "network" else cls$reason,
         next_cmd = paste("verify", email))
  }

  # Always adopt the identity Google reports (canonical, lower-case).
  mismatch <- !is.na(actual) && tolower(actual) != email
  if (mismatch) {
    say("You signed in as ", actual, " (not ", email, "). Saving ", tolower(actual),
        " as the account for Google Sheets. To use ", email, " instead, run: ",
        SETUP_SH, " auth ", email, " and pick that account in the browser.")
  }
  if (!is.na(actual)) email <- tolower(actual)

  gs_save_config_email(email)
  say("Connected as ", email, " (", GS_SCOPE_LEVEL, "). Default account saved to ", gs_config_path(), ".")
  emit("READY", email = email, reason = if (mismatch) "mismatch" else "-")
}

# ── verify -------------------------------------------------------------------
cmd_verify <- function(email_arg = NULL) {
  require_pkgs_or_exit()
  load_helpers()
  res <- tryCatch(gs_connect(email_arg), error = function(e) e)
  if (inherits(res, "error")) {
    msg <- conditionMessage(res)
    say(msg)
    if (nzchar(Sys.getenv("GS_SA_JSON", ""))) {
      emit("AUTH_FAILED", reason = if (grepl("network problem", msg)) "network" else "service-account",
           next_cmd = "fix-GS_SA_JSON")
    }
    target <- gs_resolve_email(email_arg)
    if (is.null(target)) emit("NEEDS_EMAIL", next_cmd = "auth <email>")
    if (grepl("Could not reach Google", msg)) {
      emit("AUTH_FAILED", email = target, reason = "network", next_cmd = paste("verify", target))
    }
    emit("NEEDS_AUTH", email = target, reason = "gs_connect-failed", next_cmd = paste("auth", target))
  }
  chk <- gs_live_check(googlesheets4::gs4_token(), sheets = TRUE)
  if (!chk$ok) {
    cls <- classify_auth_error(chk$message)
    say("The Sheets API host failed: ", cls$text)
    emit("AUTH_FAILED", email = res, reason = if (chk$auth_problem) "verify-failed" else "network",
         next_cmd = paste("verify", res))
  }
  say("gs4_user(): ", suppressMessages(googlesheets4::gs4_user()),
      " | scope level: ", GS_SCOPE_LEVEL, " | Sheets API: ok")
  emit("READY", email = res)
}

# ── dispatch -----------------------------------------------------------------
main <- function(args) {
  cmd   <- if (length(args) >= 1) args[[1]] else "status"
  email <- if (length(args) >= 2) args[[2]] else NULL
  switch(cmd,
    status  = cmd_status(email),
    install = cmd_install(),
    auth    = cmd_auth(email),
    verify  = cmd_verify(email),
    {
      say("Unknown command '", cmd, "'. Use: status [email] | install | auth [email] | verify [email]")
      emit("ERROR", reason = "unknown-command")
    })
}

main(commandArgs(trailingOnly = TRUE))
