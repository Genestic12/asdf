#!/usr/bin/env bash
#
# Standalone provisioning script for runpod/forge:latest.
# Run this only after Forge has completed its first startup and created:
#   /workspace/stable-diffusion-webui-forge
#
# Optional environment variables:
#   HF_TOKEN        Hugging Face access token
#   CIVITAI_TOKEN   Civitai API token
#   AUTO_UPDATE     Set to "true" to update existing extensions
#   FORGE_DIR       Override the Forge installation directory
#   VENV_PATH       Override the Forge Python virtual environment
#

set -Eeuo pipefail

FORGE_DIR="${FORGE_DIR:-/workspace/stable-diffusion-webui-forge}"
VENV_PATH="${VENV_PATH:-/workspace/venvs/stable-diffusion-webui-forge}"
AUTO_UPDATE="${AUTO_UPDATE:-false}"
MIN_FREE_GB=5

APT_PACKAGES=(
    # "package-1"
)

PIP_PACKAGES=(
    # "package-1"
)

EXTENSIONS=(
    "https://github.com/deforum-art/sd-webui-deforum"
    "https://github.com/adieyal/sd-dynamic-prompts"
    "https://github.com/AlUlkesh/stable-diffusion-webui-images-browser"
    "https://github.com/Coyote-A/ultimate-upscale-for-automatic1111"
)

CHECKPOINT_MODELS=(
    # Nova F14
    # "https://civitai.com/api/download/models/2484701?type=Model&format=SafeTensor&size=pruned&fp=fp16"

    # Nova F15.5
    # "https://civitai.com/api/download/models/2642038?type=Model&format=SafeTensor&size=pruned&fp=fp16"

    # Nova F17
    "https://civitai.com/api/download/models/2792241?type=Model&format=SafeTensor&size=pruned&fp=fp16"

    # Nova PKM
    # "https://civitai.com/api/download/models/2598129?type=Model&format=SafeTensor&size=pruned&fp=fp16"

    # Nova K8
    # "https://civitai.com/api/download/models/2765021?type=Model&format=SafeTensor&size=pruned&fp=fp16"

    # "https://civitai.com/api/download/models/2747469?type=Model&format=SafeTensor&size=pruned&fp=fp16"
    # "https://civitai.com/api/download/models/2245910?type=Model&format=SafeTensor&size=pruned&fp=fp16"
)

LORA_MODELS=(
    # "https://civitai.com/api/download/models/16576"
    # "https://civitai.com/api/download/models/1343048?type=Model&format=SafeTensor" # flared equine
    "https://civitai.com/api/download/models/1457585?type=Model&format=SafeTensor" # detailed equine female
    "https://civitai.com/api/download/models/1339237?type=Model&format=SafeTensor" # tapered cervine
    "https://civitai.com/api/download/models/1570728?type=Model&format=SafeTensor" # equine (non FAO)
    "https://civitai.com/api/download/models/1965314?type=Model&format=SafeTensor" # canine female
    "https://civitai.com/api/download/models/2149223?type=Model&format=SafeTensor" # canine male
)

VAE_MODELS=(
    # "https://huggingface.co/stabilityai/sd-vae-ft-ema-original/resolve/main/vae-ft-ema-560000-ema-pruned.safetensors"
    # "https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors"
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
)

ESRGAN_MODELS=(
    "https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x4.pth"
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"
    # "https://huggingface.co/Akumetsu971/SD_Anime_Futuristic_Armor/resolve/main/4x_NMKD-Siax_200k.pth"
)

CONTROLNET_MODELS=(
)

log() {
    printf '[provision-forge] %s\n' "$*"
}

die() {
    printf '[provision-forge] ERROR: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local exit_code=$?
    printf '[provision-forge] ERROR: command failed on line %s (exit %s)\n' \
        "${BASH_LINENO[0]}" "$exit_code" >&2
    exit "$exit_code"
}
trap on_error ERR

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

check_installation() {
    [[ -d "$FORGE_DIR" ]] || die \
        "Forge was not found at $FORGE_DIR. Let the Pod complete its first startup, then run this script again."

    [[ -x "$VENV_PATH/bin/python" ]] || die \
        "Forge virtual environment was not found at $VENV_PATH."

    require_command git
    require_command wget
    require_command df
}

check_disk_space() {
    local available_gb
    available_gb="$(
        df -Pk /workspace |
        awk 'NR == 2 { printf "%d", $4 / 1024 / 1024 }'
    )"

    log "Approximately ${available_gb} GB is free under /workspace."

    if (( available_gb < MIN_FREE_GB )); then
        die "Less than ${MIN_FREE_GB} GB is free. Expand the persistent volume before downloading the selected models."
    fi
}

install_apt_packages() {
    if (( ${#APT_PACKAGES[@]} == 0 )); then
        return
    fi

    log "Installing APT packages..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        "${APT_PACKAGES[@]}"
    rm -rf /var/lib/apt/lists/*
}

install_pip_packages() {
    if (( ${#PIP_PACKAGES[@]} == 0 )); then
        return
    fi

    log "Installing Python packages into the Forge virtual environment..."
    "$VENV_PATH/bin/pip" install --no-cache-dir "${PIP_PACKAGES[@]}"
}

install_extensions() {
    local repo dir path

    mkdir -p "$FORGE_DIR/extensions"

    for repo in "${EXTENSIONS[@]}"; do
        [[ -n "$repo" ]] || continue

        dir="${repo##*/}"
        dir="${dir%.git}"
        path="$FORGE_DIR/extensions/$dir"

        if [[ -d "$path/.git" ]]; then
            if [[ "${AUTO_UPDATE,,}" == "true" ]]; then
                log "Updating extension: $dir"
                git -C "$path" pull --ff-only
                git -C "$path" submodule update --init --recursive
            else
                log "Extension already exists; leaving unchanged: $dir"
            fi
        elif [[ -e "$path" ]]; then
            die "Extension destination exists but is not a Git repository: $path"
        else
            log "Cloning extension: $repo"
            git clone --recursive "$repo" "$path"
        fi
    done
}

download_file() {
    local url="$1"
    local destination_dir="$2"
    local token=""

    mkdir -p "$destination_dir"

    case "$url" in
        https://huggingface.co/*)
            token="${HF_TOKEN:-}"
            ;;
        https://civitai.com/*|https://www.civitai.com/*)
            token="${CIVITAI_TOKEN:-}"
            ;;
    esac

    local wget_args=(
        --continue
        --content-disposition
        --trust-server-names
        --show-progress
        --progress=bar:force:noscroll
        --directory-prefix="$destination_dir"
    )

    if [[ -n "$token" ]]; then
        wget_args+=(--header="Authorization: Bearer $token")
    fi

    log "Downloading into $destination_dir:"
    log "  $url"
    wget "${wget_args[@]}" "$url"
}

download_group() {
    local label="$1"
    local destination_dir="$2"
    shift 2
    local urls=("$@")

    if (( ${#urls[@]} == 0 )); then
        log "No $label files selected."
        return
    fi

    log "Downloading ${#urls[@]} $label file(s)..."
    local url
    for url in "${urls[@]}"; do
        [[ -n "$url" ]] || continue
        download_file "$url" "$destination_dir"
    done
}

main() {
    printf '\n'
    printf '============================================\n'
    printf ' Forge provisioning\n'
    printf '============================================\n\n'

    check_installation
    check_disk_space
    install_apt_packages
    install_pip_packages
    install_extensions

    download_group \
        "checkpoint" \
        "$FORGE_DIR/models/Stable-diffusion" \
        "${CHECKPOINT_MODELS[@]}"

    download_group \
        "LoRA" \
        "$FORGE_DIR/models/Lora" \
        "${LORA_MODELS[@]}"

    download_group \
        "ControlNet" \
        "$FORGE_DIR/models/ControlNet" \
        "${CONTROLNET_MODELS[@]}"

    download_group \
        "VAE" \
        "$FORGE_DIR/models/VAE" \
        "${VAE_MODELS[@]}"

    download_group \
        "ESRGAN" \
        "$FORGE_DIR/models/ESRGAN" \
        "${ESRGAN_MODELS[@]}"

    printf '\n'
    log "Provisioning complete."
    log "Restart Forge or restart the Pod so extensions and newly installed dependencies are loaded."
}

main "$@"
