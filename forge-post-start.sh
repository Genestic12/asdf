#!/usr/bin/env bash
#
# Runpod Forge post-start provisioning hook.
#
# Required environment variable:
#   PROVISION_SCRIPT_URL  Raw HTTPS URL to provision-forge.sh
#
# Optional:
#   PROVISION_MARKER      Change this to force a new provisioning revision.
#

set -Eeuo pipefail

PROVISION_SCRIPT_URL="${PROVISION_SCRIPT_URL:?PROVISION_SCRIPT_URL is not set}"
PROVISION_MARKER="${PROVISION_MARKER:-/workspace/.fc-forge-provisioned-v1}"
LOCAL_SCRIPT="/workspace/provision-forge.sh"

log() {
    printf '[forge-post-start] %s\n' "$*"
}

if [[ -f "$PROVISION_MARKER" ]]; then
    log "Provisioning marker already exists; skipping downloads."
else
    log "Downloading provisioning script..."
    wget \
        --quiet \
        --output-document="$LOCAL_SCRIPT" \
        "$PROVISION_SCRIPT_URL"

    chmod +x "$LOCAL_SCRIPT"

    log "Running provisioning script..."
    "$LOCAL_SCRIPT"

    touch "$PROVISION_MARKER"
    log "Provisioning completed successfully."
fi

log "Starting Forge..."
exec /start_forge.sh
