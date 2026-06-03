# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Script

```bash
./bw_export.sh
```

No arguments are accepted. The script uses `set -euo pipefail` and exits non-zero on any failure.

## File Structure

| File | Role |
|---|---|
| `bw_export.sh` | Entry point. Resolves `SCRIPT_DIR`, sources the other two files, and calls `main()`. |
| `bw_config.sh` | Configuration only. Declares all variables using `: "${VAR:=default}"` so env vars already in the environment take precedence. Derives log labels and unsets the helper function used to compute them. |
| `bw_functions.sh` | All side-effectful work. Each function does exactly one named step. |
| `.envrc` | Direnv file setting `BW_CLIENTID` and `BW_CLIENTSECRET` for API key auth. Git-ignored. |
| `.gitignore` | Ignores `logs/`, `.envrc`, `*.DS_store`. |

## Execution Order (`main`)

```
ensure_login
load_master_password
unlock_vault
load_export_password
prompt_for_unencrypted_export
ensure_save_directory
start_sync
export_personal_vault  <timestamp>
export_org_vault       <timestamp>
download_all_attachments
report_trash_items
lock_vault
```

`load_user_email` is defined in `bw_functions.sh` but is currently commented out in `main()` — login uses API key auth instead (see Credential Flow).

## Credential Flow

### API Key Login
`ensure_login` checks `bw status`. If unauthenticated, it calls `bw login --apikey`, which reads `BW_CLIENTID` and `BW_CLIENTSECRET` from the environment. These are set by `.envrc` via direnv.

### Keychain Secrets
The master password and export password come from **macOS Keychain** via `/usr/bin/security find-generic-password`. Service names are configurable in `bw_config.sh`:

| Variable | Default service name | Holds |
|---|---|---|
| `EMAIL_SERVICE` | `bw_email` | Bitwarden login email (loaded but unused in current flow) |
| `BW_SERVICE` | `bw_pass` | Master password |
| `BW_EXPORT_SERVICE` | `bw_export_pass` | Encryption password for exported JSON |

No secrets are written to disk. `BW_SESSION` is set in-process after `bw unlock`.

## Export Behavior

- If `bw_export_pass` is present in Keychain → exports use `encrypted_json` format (`.encrypted.json`).
- If absent → exports are plain JSON; user is prompted to confirm before continuing.
- Organization vault export is skipped when `ORG_ID` is empty (default).
- Master password is piped via stdin (`printf '%s\n' "$BW_PASSWORD" | bw export ...`) to avoid exposing it in the process list.

## Attachment Behavior

- All vault items with attachments are listed via `bw list items | jq`.
- Each attachment is downloaded to a temp file first, then compared with `cmp -s` against any existing copy.
- If content is identical, the temp file is discarded (no write). If new or changed, it is moved into place.
- A `trap` on `RETURN` ensures the temp file is cleaned up on any exit from the function.
- Item names are sanitized with `tr -c '[:alnum:]_.-' '_'`; names that collapse to empty fall back to the item UUID.
- Saved to: `SAVE_FOLDER_ATTACHMENTS/<sanitized_item_name>/<filename>`

## Logging

`log_write` in `bw_functions.sh` writes `[ISO8601 timestamp] [LEVEL] message` to both stdout and `$LOG_FILE`. Levels: `INFO`, `WARN`, `ERROR`.

`LOG_FILE` is set by `main()` to `logs/bw_export_<YYYYMMDD_HHMMSS>.log`. The `logs/` directory is git-ignored.

## Configuration

All variables in `bw_config.sh` use `: "${VAR:=default}"`, so they can be overridden by exporting before running:

```bash
SAVE_FOLDER=/tmp/bw_test ./bw_export.sh
```

Default export paths point to iCloud Drive under `PARA/3_Resources/Backups/BW Backups/`.

| Variable | Default |
|---|---|
| `SAVE_FOLDER` | iCloud `BW Backups/BU_Json` |
| `SAVE_FOLDER_ATTACHMENTS` | iCloud `BW Backups/Attachments` |
| `LOG_DIR` | `$SCRIPT_DIR/logs` |
| `ORG_ID` | *(empty — org export skipped)* |

## Dependencies

- `bw` (Bitwarden CLI)
- `jq`
- `security` (macOS Keychain, ships with macOS)
- `direnv` (optional — loads `.envrc`; without it, set `BW_CLIENTID` and `BW_CLIENTSECRET` manually)
