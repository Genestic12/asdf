#!/bin/bash
# This file will be sourced in init.sh
# Namespace functions with provisioning_

# https://raw.githubusercontent.com/ai-dock/stable-diffusion-webui/main/config/provisioning/default.sh

### Edit the following arrays to suit your workflow - values must be quoted and separated by newlines or spaces.
### If you specify gated models you'll need to set environment variables HF_TOKEN and/orf CIVITAI_TOKEN

DISK_GB_REQUIRED=10

APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
)

EXTENSIONS=(
    #"https://github.com/Mikubill/sd-webui-controlnet"
    "https://github.com/deforum-art/sd-webui-deforum"
    "https://github.com/adieyal/sd-dynamic-prompts"
    #"https://github.com/ototadana/sd-face-editor"
    "https://github.com/AlUlkesh/stable-diffusion-webui-images-browser"
    #"https://github.com/hako-mikan/sd-webui-regional-prompter"
    "https://github.com/Coyote-A/ultimate-upscale-for-automatic1111"
    #"https://github.com/Gourieff/sd-webui-reactor"
)

CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/2484701?type=Model&format=SafeTensor&size=pruned&fp=fp16"
    #"https://civitai.com/api/download/models/2245910?type=Model&format=SafeTensor&size=pruned&fp=fp16"
)

LORA_MODELS=(
    #"https://civitai.com/api/download/models/16576"
    #"https://civitai.com/api/download/models/1343048?type=Model&format=SafeTensor" #flared equine
    "https://civitai.com/api/download/models/1457585?type=Model&format=SafeTensor" #detailed equine female
    "https://civitai.com/api/download/models/1339237?type=Model&format=SafeTensor" #tapered cervine
    "https://civitai.com/api/download/models/1570728?type=Model&format=SafeTensor" #equine (non FAO)
    "https://civitai.com/api/download/models/1965314?type=Model&format=SafeTensor" #canine female
    "https://civitai.com/api/download/models/2149223?type=Model&format=SafeTensor" #canine male
    
)

VAE_MODELS=(
    #"https://huggingface.co/stabilityai/sd-vae-ft-ema-original/resolve/main/vae-ft-ema-560000-ema-pruned.safetensors"
    #"https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors"
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
)

ESRGAN_MODELS=(
    "https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x4.pth"
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"
    #"https://huggingface.co/Akumetsu971/SD_Anime_Futuristic_Armor/resolve/main/4x_NMKD-Siax_200k.pth"
)

CONTROLNET_MODELS=(

)


### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    # We need to apply some workarounds to make old builds work with the new default
    if [[ -z "${CIVITAI_TOKEN:-}" ]]; then
      echo "[warn] CIVITAI_TOKEN is NOT set. Some civitai downloads may fail."
    else
      echo "[info] CIVITAI_TOKEN is set (len=${#CIVITAI_TOKEN})."
    fi

    echo "[sync] removing incompatible syncthing config (if present)"
    rm -rf /workspace/home/user/.config/syncthing 2>/dev/null || true
    rm -rf /home/user/.config/syncthing 2>/dev/null || true
    pkill -f syncthing 2>/dev/null || true

    if [[ ! -d /opt/environments/python ]]; then 
        export MAMBA_BASE=true
    fi
    source /opt/ai-dock/etc/environment.sh
    source /opt/ai-dock/bin/venv-set.sh webui

    DISK_GB_AVAILABLE=$(($(df --output=avail -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_USED=$(($(df --output=used -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_ALLOCATED=$(($DISK_GB_AVAILABLE + $DISK_GB_USED))
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_pip_packages
    provisioning_get_extensions
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/ckpt" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/lora" \
        "${LORA_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
     
    PLATFORM_ARGS=""
    if [[ $XPU_TARGET = "CPU" ]]; then
        PLATFORM_ARGS="--use-cpu all --skip-torch-cuda-test --no-half"
    fi
    PROVISIONING_ARGS="--skip-python-version-check --no-download-sd-model --do-not-download-clip --port 11404 --exit"
    ARGS_COMBINED="${PLATFORM_ARGS} $(cat /etc/a1111_webui_flags.conf) ${PROVISIONING_ARGS}"
    
    # Start and exit because webui will probably require a restart
    cd /opt/stable-diffusion-webui
    if [[ -z $MAMBA_BASE ]]; then
        source "$WEBUI_VENV/bin/activate"
        LD_PRELOAD=libtcmalloc.so python launch.py \
            ${ARGS_COMBINED}
        deactivate
    else 
        micromamba run -n webui -e LD_PRELOAD=libtcmalloc.so python launch.py \
            ${ARGS_COMBINED}
    fi
    provisioning_print_end
}

function pip_install() {
    if [[ -z $MAMBA_BASE ]]; then
            "$WEBUI_VENV_PIP" install --no-cache-dir "$@"
        else
            micromamba run -n webui pip install --no-cache-dir "$@"
        fi
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip_install ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_extensions() {
    for repo in "${EXTENSIONS[@]}"; do
        dir="${repo##*/}"
        path="/opt/stable-diffusion-webui/extensions/${dir}"
        if [[ -d $path ]]; then
            # Pull only if AUTO_UPDATE
            if [[ ${AUTO_UPDATE,,} == "true" ]]; then
                printf "Updating extension: %s...\n" "${repo}"
                ( cd "$path" && git pull )
            fi
        else
            printf "Downloading extension: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
        fi
    done
}

function provisioning_get_models() {
  if [[ -z $2 ]]; then return 1; fi
  dir="$1"
  mkdir -p "$dir"
  shift

  # Keep warning, but download all requested models anyway
  if [[ $DISK_GB_ALLOCATED -lt $DISK_GB_REQUIRED ]]; then
    printf "WARNING: Low disk space allocation (%sGB < %sGB). Attempting all downloads anyway.\n" \
      "$DISK_GB_ALLOCATED" "$DISK_GB_REQUIRED"
  fi

  arr=("$@")
  printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
  for url in "${arr[@]}"; do
    printf "Downloading: %s\n" "${url}"
    provisioning_download "${url}" "${dir}"
    printf "\n"
  done
}


function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
    if [[ $DISK_GB_ALLOCATED -lt $DISK_GB_REQUIRED ]]; then
        printf "WARNING: Your allocated disk size (%sGB) is below the recommended %sGB - Some models will not be downloaded\n" "$DISK_GB_ALLOCATED" "$DISK_GB_REQUIRED"
    fi
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Web UI will start now\n\n"
}


# Download from $1 URL to $2 file path
function provisioning_download() {
  local url="$1"
  local outdir="$2"

  mkdir -p "$outdir"

  # Add token headers only for the origin hosts.
  local headers=()
  if [[ -n "${HF_TOKEN:-}" && "$url" == *"huggingface.co"* ]]; then
    headers+=(-H "Authorization: Bearer ${HF_TOKEN}")
  elif [[ -n "${CIVITAI_TOKEN:-}" && "$url" == *"civitai.com"* ]]; then
    headers+=(-H "Authorization: Bearer ${CIVITAI_TOKEN}")
  fi

  echo "[download] $url"

  # Print final HTTP code for visibility (doesn't download yet).
  local code
  code="$(curl -sS -L -o /dev/null -w "%{http_code}" -A "Mozilla/5.0" "${headers[@]}" "$url" || true)"
  echo "[download] http=$code"

  # Actual download (follows redirect to R2)
  curl -fL -A "Mozilla/5.0" \
    --retry 15 --retry-delay 3 --retry-connrefused \
    -C - -OJ \
    "${headers[@]}" \
    --output-dir "$outdir" \
    "$url"
}




provisioning_start
