#!/bin/bash
# Helper functions for Bitwarden export automation.

load_user_email() {
    echo "Fetching Bitwarden username from Keychain service '$EMAIL_SERVICE'..."
    if ! USER_EMAIL=$(/usr/bin/security find-generic-password -s "$EMAIL_SERVICE" -w 2>/dev/null)
    then
        echo "ERROR: Failed to retrieve Bitwarden username from the Keychain (service: $EMAIL_SERVICE)."
        echo
        exit 1
    else
        echo "Bitwarden username retrieved: $USER_EMAIL"
        echo
    fi
}

load_master_password() {
    echo "Retrieving Bitwarden master password from Keychain service '$BW_SERVICE'..."

    if ! BW_PASSWORD=$(/usr/bin/security find-generic-password -s "$BW_SERVICE" -w 2>/dev/null)
    then
        echo "ERROR: Failed to retrieve bw password from the Keychain (service: $BW_SERVICE)."
        echo
        exit 1
    else
        echo "Master password retrieved successfully."
        echo
    fi
}

ensure_login() {
    echo "Verifying Bitwarden CLI authentication status..."
    if [[ $(bw status | jq -r .status) == "unauthenticated" ]]
    then
        echo "No active session detected. Logging in with saved credentials..."
        bw login "$USER_EMAIL" "$BW_PASSWORD" --method 0 --quiet
    else
        echo "Bitwarden CLI already authenticated."
    fi

    if [[ $(bw status | jq -r .status) == "unauthenticated" ]]
    then
        echo "ERROR: Failed to authenticate."
        echo
        exit 1
    fi
}

unlock_vault() {
    echo "Unlocking Bitwarden vault..."
    SESSION_KEY=$(bw unlock "$BW_PASSWORD" --raw)

    if [[ -z "$SESSION_KEY" ]]
    then
        echo "ERROR: Failed to authenticate."
        echo
        exit 1
    else
        echo "Vault unlocked successfully."
        echo
    fi

    export BW_SESSION="$SESSION_KEY"
}

load_export_password() {
    echo "Retrieving export password from Keychain service '$BW_EXPORT_SERVICE'..."

    if ! BW_EXPORT_PASSWORD=$(/usr/bin/security find-generic-password -s "$BW_EXPORT_SERVICE" -w 2>/dev/null)
    then
        echo "ERROR: Failed to retrieve bw export password from the Keychain (service: $BW_EXPORT_SERVICE)."
        echo
        exit 1
    else
        echo "Export password retrieved successfully."
        echo
    fi
}

prompt_for_unencrypted_export() {
    if [[ -n "$BW_EXPORT_PASSWORD" ]]
    then
        return
    fi

    echo "No export password found."
    echo -e -n "\033[0;33m"
    echo "WARNING! Vault contents will be written to disk without encryption."
    echo -e -n "\033[0m"

    local continue_choice=""
    until [[ $continue_choice =~ (y|n) ]]
    do
        read -rp "Continue? [y/n]: " -e continue_choice
    done

    if [[ $continue_choice == "n" ]]
    then
        echo "Exiting script."
        echo
        exit 1
    fi
}

ensure_save_directory() {
    if [[ ! -d "$SAVE_FOLDER" ]]
    then
        echo "ERROR: Could not find the export destination folder: $SAVE_FOLDER"
        echo
        exit 1
    else
        echo "Export destination confirmed: $SAVE_FOLDER_LABEL"
    fi
}

export_personal_vault() {
    local timestamp="$1"
    local personal_export_base="$SAVE_FOLDER/bitwarden_personal_$timestamp"
    local personal_log_base="$SAVE_FOLDER_LABEL/bitwarden_personal_$timestamp"

    if [[ -z "$BW_EXPORT_PASSWORD" ]]
    then
        echo
        echo "Exporting personal vault (unencrypted JSON) to ${personal_log_base}.json..."
        bw export --format json --output "${personal_export_base}.json"
    else
        echo
        echo "Exporting personal vault (encrypted JSON) to ${personal_log_base}.encrypted.json..."
        bw export --format encrypted_json --password "$BW_EXPORT_PASSWORD" --output "${personal_export_base}.encrypted.json"
    fi
}

export_org_vault() {
    local timestamp="$1"
    local org_export_base="$SAVE_FOLDER/bitwarden_organization_$timestamp"
    local org_log_base="$SAVE_FOLDER_LABEL/bitwarden_organization_$timestamp"

    if [[ -z "$ORG_ID" ]]
    then
        echo
        echo "Organization export skipped: no ORG_ID configured."
        return
    fi

    if [[ -z "$BW_EXPORT_PASSWORD" ]]
    then
        echo
        echo "Exporting organization vault (unencrypted JSON) to ${org_log_base}.json..."
        bw export --organizationid "$ORG_ID" --format json --output "${org_export_base}.json"
    else
        echo
        echo "Exporting organization vault (encrypted JSON) to ${org_log_base}.encrypted.json..."
        bw export --organizationid "$ORG_ID" --format encrypted_json --password "$BW_EXPORT_PASSWORD" --output "${org_export_base}.encrypted.json"
    fi
}

download_all_attachments() {
    local attachment_lines
    local safe_item_name
    local target_dir

    attachment_lines=$(bw list items | jq -r '.[]
        | select(.attachments != null)
        | . as $item
        | .attachments[]
        | [$item.id, $item.name, .fileName]
        | @tsv')

    if [[ -n "$attachment_lines" ]]
    then
        echo
        echo "Saving attachments to $SAVE_FOLDER_ATTACHMENTS_LABEL..."
        while IFS=$'\t' read -r item_id item_name attachment_filename || [[ -n "$item_id" ]]
        do
            safe_item_name=$(printf '%s' "$item_name" | tr -c '[:alnum:]_.-' '_')
            [[ -z "$safe_item_name" ]] && safe_item_name="$item_id"
            target_dir="$SAVE_FOLDER_ATTACHMENTS/$safe_item_name"
            mkdir -p "$target_dir"
            echo "  - Downloading attachment '$attachment_filename' for item '$item_name' into $SAVE_FOLDER_ATTACHMENTS_LABEL/$safe_item_name"
            bw get attachment "$attachment_filename" --itemid "$item_id" --output "$target_dir/"
        done <<< "$attachment_lines"
    else
        echo
        echo "No attachments detected in the vault; skipping attachment download."
    fi
}

report_trash_items() {
    local trash_count
    trash_count=$(bw list items --trash | jq -r '. | length')

    if (( trash_count > 0 ))
    then
        echo -e -n "\033[0;33m"
        echo "Reminder: $trash_count item(s) remain in Bitwarden Trash and were not included in the export."
        echo -e -n "\033[0m"
    else
        echo "Trash check: no deleted items found; export includes everything available."
    fi
}

lock_vault() {
    echo "Locking Bitwarden CLI session..."
    bw lock
}
