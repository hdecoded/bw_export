# Bitwarden Export Automation

Backs up your Bitwarden vault (personal + optional organization) and downloads all file attachments in one command.

## How It Works

Running `./bw_export.sh` executes this sequence:

1. Checks Bitwarden CLI login status — authenticates via API key if needed
2. Loads the master password from Keychain and unlocks the vault
3. Loads the export password from Keychain (determines encrypted vs plain JSON)
4. Syncs the vault (`bw sync`) to ensure data is current
5. Exports the personal vault JSON
6. Exports the organization vault JSON (if `ORG_ID` is configured)
7. Downloads all file attachments, skipping files that haven't changed
8. Reports any items sitting in Bitwarden Trash (not exported by the CLI)
9. Locks the vault

Everything is logged to `logs/bw_export_<timestamp>.log` and printed to stdout.

## Requirements

- macOS
- Bash 3.2+
- [Bitwarden CLI](https://bitwarden.com/help/cli/) (`bw`)
- [`jq`](https://github.com/stedolan/jq)
- [direnv](https://direnv.net/) (recommended — loads API key credentials automatically)

## One-Time Setup

### 1. Get your Bitwarden API key

In Bitwarden web vault → Account Settings → Security → API Key. Note the `client_id` and `client_secret`.

### 2. Create `.envrc` with your API key

```bash
export BW_CLIENTID=your.client_id_here
export BW_CLIENTSECRET=your_client_secret_here
```

Then allow direnv to load it:

```bash
direnv allow .
```

Without direnv, export both variables in your shell before running the script.

### 3. Store credentials in macOS Keychain

```bash
# Bitwarden master password
security add-generic-password -a "$USER" -s bw_pass -w "your-master-password"

# Export encryption password (optional — omit for plain JSON exports)
security add-generic-password -a "$USER" -s bw_export_pass -w "strong-export-password"
```

To remove a Keychain entry later:

```bash
security delete-generic-password -s bw_pass
```

### 4. Configure export paths

Edit `bw_config.sh` to set where exports are saved:

```bash
: "${SAVE_FOLDER:=/path/to/json/backups}"
: "${SAVE_FOLDER_ATTACHMENTS:=/path/to/attachment/backups}"

# Optional: set your organization ID for shared vault exports
: "${ORG_ID:=}"
```

## Running

```bash
./bw_export.sh
```

The script accepts no arguments. It exits non-zero on any failure, so it's safe to use in automated pipelines.

## What Gets Exported

| Output | Location | Format |
|---|---|---|
| Personal vault | `SAVE_FOLDER/bitwarden_personal_<timestamp>.json` | Plain JSON or `.encrypted.json` |
| Organization vault | `SAVE_FOLDER/bitwarden_organization_<timestamp>.json` | Plain JSON or `.encrypted.json` |
| Attachments | `SAVE_FOLDER_ATTACHMENTS/<item_name>/<filename>` | Original files |

**Encrypted vs plain JSON** — determined by whether `bw_export_pass` exists in Keychain. If it does, exports use Bitwarden's `encrypted_json` format. If not, the script warns and asks for confirmation before writing plain JSON.

**Attachments** — item names are sanitized to filesystem-safe strings (alphanumeric, `_`, `.`, `-`); names that collapse to empty fall back to the item UUID. Files that already exist and are unchanged are skipped.

**Trash items** — Bitwarden CLI cannot export trashed items. The script reports the count at the end so you can purge or restore manually.

## Safety Notes

- No secrets are written to disk — master password and export password come from Keychain at runtime; API credentials come from the environment.
- Master password is piped via stdin to `bw` to avoid exposing it in the process list.
- `set -euo pipefail` stops the script on any error or undefined variable.
- The CLI session is explicitly locked at the end of every run.
