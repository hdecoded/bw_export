#!/bin/bash
# Helper functions for Bitwarden export automation.

log_write() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%dT%H:%M:%S%z")
    local formatted="[$timestamp] [$level] $message"

    if [[ -n "${LOG_FILE:-}" ]]
    then
        printf '%s\n' "$formatted" >> "$LOG_FILE"
    fi

    printf '%s\n' "$formatted"
}

log_info() {
    log_write "INFO" "$1"
}

log_warn() {
    log_write "WARN" "$1"
}

log_error() {
    log_write "ERROR" "$1"
}

load_user_email() {
    log_info "Loading Bitwarden email from Keychain ($EMAIL_SERVICE)..."
    if ! USER_EMAIL=$(/usr/bin/security find-generic-password -s "$EMAIL_SERVICE" -w 2>/dev/null)
    then
        log_error "Keychain lookup failed for service $EMAIL_SERVICE."
        exit 1
    else
        log_info "Bitwarden email loaded."
    fi
}

load_master_password() {
    log_info "Loading Bitwarden master password (service $BW_SERVICE)..."

    if ! BW_PASSWORD=$(/usr/bin/security find-generic-password -s "$BW_SERVICE" -w 2>/dev/null)
    then
        log_error "Keychain lookup failed for master password service $BW_SERVICE."
        exit 1
    else
        log_info "Master password retrieved."
    fi
}

ensure_login() {
    log_info "Checking Bitwarden CLI session..."
    if [[ $(bw status | jq -r .status) == "unauthenticated" ]]
    then
        log_info "Authenticating Bitwarden CLI session..."
        bw login "$USER_EMAIL" "$BW_PASSWORD" --method 0 --quiet
    fi

    if [[ $(bw status | jq -r .status) == "unauthenticated" ]]
    then
        log_error "Bitwarden CLI authentication failed."
        exit 1
    else
        log_info "Bitwarden CLI authenticated."
    fi
}

unlock_vault() {
    log_info "Unlocking Bitwarden vault..."
    SESSION_KEY=$(bw unlock "$BW_PASSWORD" --raw)

    if [[ -z "$SESSION_KEY" ]]
    then
        log_error "Vault unlock failed."
        exit 1
    else
        log_info "Vault unlocked."
    fi

    export BW_SESSION="$SESSION_KEY"
}

load_export_password() {
    log_info "Loading export password (service $BW_EXPORT_SERVICE)..."

    if ! BW_EXPORT_PASSWORD=$(/usr/bin/security find-generic-password -s "$BW_EXPORT_SERVICE" -w 2>/dev/null)
    then
        log_error "Keychain lookup failed for export password service $BW_EXPORT_SERVICE."
        exit 1
    else
        log_info "Export password retrieved."
    fi
}

prompt_for_unencrypted_export() {
    if [[ -n "$BW_EXPORT_PASSWORD" ]]
    then
        return
    fi

    log_warn "No export password configured; personal and organization exports will be plain JSON."

    local continue_choice=""
    until [[ $continue_choice =~ (y|n) ]]
    do
        read -rp "Continue? [y/n]: " -e continue_choice
    done

    if [[ $continue_choice == "n" ]]
    then
        log_info "Export canceled by user."
        exit 1
    fi
}

ensure_save_directory() {
    if [[ ! -d "$SAVE_FOLDER" ]]
    then
        log_error "Export folder missing: $SAVE_FOLDER"
        exit 1
    else
        log_info "Writing vault exports to $SAVE_FOLDER_LABEL."
    fi
}

export_personal_vault() {
    local timestamp="$1"
    local personal_export_base="$SAVE_FOLDER/bitwarden_personal_$timestamp"
    local personal_log_base="$SAVE_FOLDER_LABEL/bitwarden_personal_$timestamp"

    if [[ -z "$BW_EXPORT_PASSWORD" ]]
    then
        log_info "Exporting personal vault to ${personal_log_base}.json (unencrypted)."
        bw export --format json --output "${personal_export_base}.json"
    else
        log_info "Exporting personal vault to ${personal_log_base}.encrypted.json (encrypted)."
        bw export --format encrypted_json --password "$BW_EXPORT_PASSWORD" --output "${personal_export_base}.encrypted.json"
    fi
}

export_org_vault() {
    local timestamp="$1"
    local org_export_base="$SAVE_FOLDER/bitwarden_organization_$timestamp"
    local org_log_base="$SAVE_FOLDER_LABEL/bitwarden_organization_$timestamp"

    if [[ -z "$ORG_ID" ]]
    then
        log_info "Organization export skipped (ORG_ID not set)."
        return
    fi

    if [[ -z "$BW_EXPORT_PASSWORD" ]]
    then
        log_info "Exporting organization vault to ${org_log_base}.json (unencrypted)."
        bw export --organizationid "$ORG_ID" --format json --output "${org_export_base}.json"
    else
        log_info "Exporting organization vault to ${org_log_base}.encrypted.json (encrypted)."
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
        log_info "Saving attachments under $SAVE_FOLDER_ATTACHMENTS_LABEL."
        while IFS=$'\t' read -r item_id item_name attachment_filename || [[ -n "$item_id" ]]
        do
            safe_item_name=$(printf '%s' "$item_name" | tr -c '[:alnum:]_.-' '_')
            [[ -z "$safe_item_name" ]] && safe_item_name="$item_id"
            target_dir="$SAVE_FOLDER_ATTACHMENTS/$safe_item_name"
            mkdir -p "$target_dir"
            log_info "Attachment saved: $SAVE_FOLDER_ATTACHMENTS_LABEL/$safe_item_name/$attachment_filename"
            bw get attachment "$attachment_filename" --itemid "$item_id" --output "$target_dir/"
        done <<< "$attachment_lines"
    else
        log_info "No attachments detected; skipping attachment download."
    fi
}

report_trash_items() {
    local trash_count
    trash_count=$(bw list items --trash | jq -r '. | length')

    if (( trash_count > 0 ))
    then
        log_warn "$trash_count item(s) remain in Bitwarden Trash; they were not exported."
    else
        log_info "Trash empty; exports include all active items."
    fi
}

lock_vault() {
    log_info "Locking Bitwarden CLI session..."
    bw lock
}
