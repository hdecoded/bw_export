# Bitwarden Export Automation

Utility scripts that back up your Bitwarden vault (personal + organization) and download all Bitwarden file attachments in one go.

## Script Overview
- `bw_export.sh` – orchestrator you run (`./bw_export.sh`). Loads configuration, sources helpers, executes the backup workflow, and relocks the CLI session when finished.
- `bw_config.sh` – central configuration. Defines where exports land, which Keychain services hold credentials, and the organization ID (optional).
- `bw_functions.sh` – reusable helper functions. Handles Keychain lookups, Bitwarden authentication/unlock, exports, attachment downloads, and final reporting.

## Requirements
- macOS (or any Bash environment with equivalent Keychain commands)
- Bash 3.2+ (macOS default is fine)
- Bitwarden CLI (`bw`) – <https://bitwarden.com/help/cli/>
- `jq` for JSON parsing – <https://github.com/stedolan/jq/>

## Where Backups Are Stored
The locations come from `bw_config.sh`; typical defaults are:
- `SAVE_FOLDER` → `/path/to/bitwarden/json/backups`  
  Contains the exported JSON files. Personal and organization vaults are named `bitwarden_<scope>_<timestamp>.json` or `.encrypted.json`.
- `SAVE_FOLDER_ATTACHMENTS` → `/path/to/bitwarden/attachment/backups`  
  Contains attachment folders. Each vault item with attachments gets its own subfolder.

Change these paths in `bw_config.sh` (or override via environment variables) to match your environment.

## One-Time Setup on macOS
1. **Configure output folders**  
   Edit `bw_config.sh` and set `SAVE_FOLDER`, `SAVE_FOLDER_ATTACHMENTS`, and (optionally) `ORG_ID`.

2. **Store Bitwarden secrets in the Keychain**  
   ```bash
   # Bitwarden login email
   security add-generic-password -a "$USER" -s bw_email -w "name@example.com"

   # Bitwarden master password
   security add-generic-password -a "$USER" -s bw_pass -w "your-master-password"

   # Optional export password (produces encrypted JSON)
   security add-generic-password -a "$USER" -s bw_export_pass -w "strong-export-password"
   ```
   Remove a secret later with `security delete-generic-password -s <service-name>`.

## Running the Backup
```bash
cd /path/to/bw_export
./bw_export.sh
```

During the run you will see step-by-step logging:
- Confirmation that the email, master password, and export password were retrieved from the Keychain.
- Authentication status (login + vault unlock).
- Export locations displayed using friendly labels (`BW Backups/...` and `Attachments/...`).
- Attachment download progress (each file lists its destination).
- Trash summary noting items that Bitwarden CLI cannot export.

The script exits non-zero if any critical step fails (missing Keychain item, export directory, login failure, etc.), so automation layers can detect issues.

## What Gets Exported
- **Personal vault JSON**  
  Stored under `SAVE_FOLDER` as `bitwarden_personal_<timestamp>.json` (unencrypted) or `.encrypted.json` (when `bw_export_pass` exists).
- **Organization vault JSON** (when `ORG_ID` is set)  
  Stored under `SAVE_FOLDER` as `bitwarden_organization_<timestamp>.json` or `.encrypted.json`.
- **Attachments**  
  Downloaded into `SAVE_FOLDER_ATTACHMENTS/<item_name>/`. Item names are sanitized to filesystem-safe strings; empty names fall back to the item ID.

Items that live in the Bitwarden Trash are not included—Bitwarden’s CLI cannot export them. The script highlights the trash count after the backup so you can purge or restore as needed.

## Safety Notes
- No secrets are written to disk; everything comes from the Keychain at runtime.
- `set -euo pipefail` is enabled to stop on errors and undefined variables.
- The Bitwarden CLI session is explicitly locked again at the end of the run.

Run `./bw_export.sh --help` for standard Bash usage details (the script accepts no additional arguments, but forwards any provided options to the helper functions). Make sure you inspect and adapt the scripts to match your security requirements before relying on them for regular backups.
