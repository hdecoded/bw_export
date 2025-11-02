#!/bin/bash
# Shared configuration for Bitwarden export automation.
# Override these values by editing this file or exporting env vars before running the script.

# Path to store personal and organizational vault exports.
: "${SAVE_FOLDER:=/Users/hd/Library/Mobile Documents/com~apple~CloudDocs/PARA/3_Resources/Backups/BW Backups/BU_Json}"

# Path to store downloaded attachments (one subfolder per vault item).
: "${SAVE_FOLDER_ATTACHMENTS:=/Users/hd/Library/Mobile Documents/com~apple~CloudDocs/PARA/3_Resources/Backups/BW Backups/Attachments}"

# macOS Keychain service names for Bitwarden credentials.
: "${EMAIL_SERVICE:=bw_email}"
: "${BW_SERVICE:=bw_pass}"
: "${BW_EXPORT_SERVICE:=bw_export_pass}"

# Organization ID for shared-vault exports (leave empty for personal-only backups).
: "${ORG_ID:=}"

# Labels used in log output to avoid printing full filesystem paths.
_bw_config__derive_label() {
    local path="$1"
    local prefer_parent="$2"
    local candidate

    if [[ "$prefer_parent" == "parent" ]]
    then
        candidate=$(basename "$(dirname "$path")")
    else
        candidate=$(basename "$path")
    fi

    if [[ "$candidate" == "." || "$candidate" == "/" ]]
    then
        candidate=$(basename "$path")
    fi

    printf '%s' "$candidate"
}

: "${SAVE_FOLDER_LABEL:=$(_bw_config__derive_label "$SAVE_FOLDER" "parent")}"
: "${SAVE_FOLDER_ATTACHMENTS_LABEL:=$(_bw_config__derive_label "$SAVE_FOLDER_ATTACHMENTS" "self")}"

unset -f _bw_config__derive_label
