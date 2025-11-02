#!/bin/bash
set -euo pipefail

# Bitwarden CLI Vault Export Script
# Coordinates configuration loading and helper routines to export Bitwarden data.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/bw_config.sh"
source "$SCRIPT_DIR/bw_functions.sh"

main() {
    echo "Launching Bitwarden backup workflow..."

    load_user_email
    load_master_password
    ensure_login
    unlock_vault
    load_export_password
    prompt_for_unencrypted_export

    echo "Preparing export targets and retrieving data..."
    ensure_save_directory

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    export_personal_vault "$timestamp"
    export_org_vault "$timestamp"
    download_all_attachments

    echo
    echo "Bitwarden vault export completed successfully."

    report_trash_items

    echo
    lock_vault
    echo
}

main "$@"
