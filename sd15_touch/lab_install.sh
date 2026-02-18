#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# lab_install.sh — Add sd15_touch models and custom nodes to an existing
#                  ComfyUI installation (source or Desktop app)
#
# Designed for UVA lab Macs where ComfyUI is already installed.
# Run once per machine; safe to re-run (skips already-downloaded files).
#
# Usage:
#   bash lab_install.sh                             # auto-detect ComfyUI folder
#   bash lab_install.sh --comfyui-path /path/to/ComfyUI
#
# What it does:
#   1. Finds (or is told) where ComfyUI stores its data (models/, custom_nodes/)
#   2. Installs ComfyUI Manager + custom nodes (IPAdapter Plus, ControlNet Aux)
#   3. Downloads all required model weights (~7 GB)
#   4. Copies workflow JSONs into ComfyUI/API/
#   5. Creates a "Launch ComfyUI" icon on the Desktop
# ─────────────────────────────────────────────────────────────────────────────

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}▶${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
error() { echo -e "${RED}✖${NC}  $*"; exit 1; }
step()  { echo -e "\n${BOLD}── $* ────────────────────────────────────────────────────────────${NC}"; }

# ── 1. Parse args + auto-detect ComfyUI path ─────────────────────────────────
step "Locating ComfyUI"

COMFYUI_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --comfyui-path)
            COMFYUI_PATH="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash lab_install.sh [--comfyui-path /path/to/ComfyUI]"
            echo ""
            echo "If --comfyui-path is omitted, common locations are searched automatically."
            echo "The path should be the folder that contains models/ and custom_nodes/."
            exit 0 ;;
        *)
            error "Unknown argument: $1. Use --help for usage." ;;
    esac
done

if [ -z "$COMFYUI_PATH" ]; then
    info "No --comfyui-path given — searching common locations…"
    for candidate in \
        "$HOME/Library/Application Support/ComfyUI" \
        "$HOME/Documents/ComfyUI" \
        "$HOME/Desktop/ComfyUI" \
        "$HOME/ComfyUI" \
        "$HOME/Downloads/ComfyUI"; do
        if [ -d "$candidate/models" ] && [ -d "$candidate/custom_nodes" ]; then
            COMFYUI_PATH="$candidate"
            info "Found: $COMFYUI_PATH"
            break
        fi
    done
fi

if [ -z "$COMFYUI_PATH" ]; then
    error "Could not find a ComfyUI data folder automatically.
  Please run with the path explicitly:
    bash lab_install.sh --comfyui-path /path/to/ComfyUI"
fi

if [ ! -d "$COMFYUI_PATH/models" ] || [ ! -d "$COMFYUI_PATH/custom_nodes" ]; then
    error "$COMFYUI_PATH does not look like a ComfyUI folder (missing models/ or custom_nodes/).
  Check the path and try again."
fi

info "ComfyUI path: $COMFYUI_PATH"

# ── 2. Detect install type ────────────────────────────────────────────────────
step "Detecting ComfyUI install type"

INSTALL_TYPE="desktop"
COMFY_VENV=""

if [ -f "$COMFYUI_PATH/main.py" ]; then
    INSTALL_TYPE="source"
    info "Source install detected (main.py found)"
    # Look for an associated venv
    for venv_candidate in \
        "$COMFYUI_PATH/venv" \
        "$COMFYUI_PATH/../venv" \
        "$(dirname "$COMFYUI_PATH")/venv"; do
        if [ -f "$venv_candidate/bin/activate" ]; then
            COMFY_VENV="$venv_candidate"
            info "Found venv: $COMFY_VENV"
            break
        fi
    done
else
    info "Desktop app install detected (no main.py)"
fi

# ── 3. Python + huggingface_hub setup ─────────────────────────────────────────
step "Setting up huggingface_hub for model downloads"

DL_VENV="$SCRIPT_DIR/.dl_venv"
HFCLI=""

# Prefer an already-active huggingface-cli
if command -v huggingface-cli &>/dev/null; then
    HFCLI="huggingface-cli"
    info "huggingface-cli already available on PATH."
elif [ -n "$COMFY_VENV" ]; then
    # Use the ComfyUI venv if it has huggingface_hub
    if "$COMFY_VENV/bin/pip" show huggingface_hub &>/dev/null 2>&1; then
        HFCLI="$COMFY_VENV/bin/huggingface-cli"
        info "Using huggingface-cli from ComfyUI venv."
    fi
fi

if [ -z "$HFCLI" ]; then
    command -v python3 >/dev/null || error "python3 not found. Install Python 3.10+ first."
    info "Creating minimal download venv at .dl_venv…"
    python3 -m venv "$DL_VENV"
    "$DL_VENV/bin/pip" install --upgrade pip --quiet
    "$DL_VENV/bin/pip" install huggingface_hub --quiet
    HFCLI="$DL_VENV/bin/huggingface-cli"
    info "huggingface-cli installed in .dl_venv."
fi

# ── download_if_missing helper ────────────────────────────────────────────────
download_if_missing() {
    local dest="$1"; local repo="$2"; local file="$3"; local dir="$4"
    if [ ! -f "$dest" ]; then
        info "Downloading $(basename "$dest")…"
        "$HFCLI" download "$repo" "$file" --local-dir "$dir" \
            --local-dir-use-symlinks False
    else
        info "$(basename "$dest") already present — skipping."
    fi
}

# ── 4. ComfyUI Manager ────────────────────────────────────────────────────────
step "ComfyUI Manager"
CUSTOM_NODES="$COMFYUI_PATH/custom_nodes"

if [ ! -d "$CUSTOM_NODES/ComfyUI-Manager/.git" ]; then
    info "Cloning ComfyUI-Manager…"
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
        "$CUSTOM_NODES/ComfyUI-Manager" --depth 1
else
    info "ComfyUI-Manager already present."
fi

# ── 5. Custom nodes ───────────────────────────────────────────────────────────
step "Custom nodes"

if [ ! -d "$CUSTOM_NODES/ComfyUI_IPAdapter_plus/.git" ]; then
    info "Cloning ComfyUI_IPAdapter_plus…"
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git \
        "$CUSTOM_NODES/ComfyUI_IPAdapter_plus" --depth 1
else
    info "ComfyUI_IPAdapter_plus already present."
fi

if [ ! -d "$CUSTOM_NODES/comfyui_controlnet_aux/.git" ]; then
    info "Cloning comfyui_controlnet_aux…"
    git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git \
        "$CUSTOM_NODES/comfyui_controlnet_aux" --depth 1
else
    info "comfyui_controlnet_aux already present."
fi

info "Copying WebSocket image node…"
cp "$SCRIPT_DIR/td_integration/custom_nodes/websocket_image_save.py" \
   "$CUSTOM_NODES/websocket_image_save.py"

# ── 6. Install custom node requirements (source install only) ─────────────────
if [ "$INSTALL_TYPE" = "source" ] && [ -n "$COMFY_VENV" ]; then
    step "Installing custom node requirements (source install)"
    source "$COMFY_VENV/bin/activate"
    pip install -r "$CUSTOM_NODES/ComfyUI_IPAdapter_plus/requirements.txt" --quiet
    pip install -r "$CUSTOM_NODES/comfyui_controlnet_aux/requirements.txt" --quiet
    deactivate 2>/dev/null || true
    info "Custom node requirements installed."
elif [ "$INSTALL_TYPE" = "desktop" ]; then
    info "Desktop install: ComfyUI Manager will handle custom node requirements on first launch."
fi

# ── 7. Model downloads ────────────────────────────────────────────────────────
step "Model downloads (~7 GB total — this will take a while)"

CKPT="$COMFYUI_PATH/models/checkpoints"
LORA="$COMFYUI_PATH/models/loras"
CNET="$COMFYUI_PATH/models/controlnet"
IPAD="$COMFYUI_PATH/models/ipadapter"
CLIP_DIR="$COMFYUI_PATH/models/clip_vision"

# Create directories if they don't exist
mkdir -p "$CKPT" "$LORA" "$CNET" "$IPAD" "$CLIP_DIR"

# SD 1.5 checkpoint (~4 GB)
download_if_missing \
    "$CKPT/v1-5-pruned-emaonly.safetensors" \
    "stable-diffusion-v1-5/stable-diffusion-v1-5" \
    "v1-5-pruned-emaonly.safetensors" \
    "$CKPT"

# LCM LoRA (~400 MB)
download_if_missing \
    "$LORA/pytorch_lora_weights.safetensors" \
    "latent-consistency/lcm-lora-sdv1-5" \
    "pytorch_lora_weights.safetensors" \
    "$LORA"

# ControlNet Canny (~700 MB)
download_if_missing \
    "$CNET/control_v11p_sd15_canny_fp16.safetensors" \
    "lllyasviel/ControlNet-v1-1" \
    "control_v11p_sd15_canny_fp16.safetensors" \
    "$CNET"

# ControlNet Depth (~700 MB)
download_if_missing \
    "$CNET/control_v11f1p_sd15_depth_fp16.safetensors" \
    "lllyasviel/ControlNet-v1-1" \
    "control_v11f1p_sd15_depth_fp16.safetensors" \
    "$CNET"

# IP-Adapter Plus SD1.5 (~800 MB)
download_if_missing \
    "$IPAD/ip-adapter-plus_sd15.bin" \
    "h94/IP-Adapter" \
    "models/ip-adapter-plus_sd15.bin" \
    "$IPAD"
# huggingface-cli nests the path — flatten it
if [ -f "$IPAD/models/ip-adapter-plus_sd15.bin" ] && [ ! -f "$IPAD/ip-adapter-plus_sd15.bin" ]; then
    mv "$IPAD/models/ip-adapter-plus_sd15.bin" "$IPAD/ip-adapter-plus_sd15.bin"
    rmdir "$IPAD/models" 2>/dev/null || true
fi

# CLIP Vision ViT-H/14 (~3.9 GB) — required by IP-Adapter
CLIP_TARGET="$CLIP_DIR/CLIP-ViT-H-14-laion2B-s32B-b79K.bin"
if [ ! -f "$CLIP_TARGET" ]; then
    info "Downloading CLIP-ViT-H-14 (~3.9 GB)…"
    "$HFCLI" download "laion/CLIP-ViT-H-14-laion2B-s32B-b79K" \
        "open_clip_pytorch_model.bin" \
        --local-dir "$CLIP_DIR" \
        --local-dir-use-symlinks False
    mv "$CLIP_DIR/open_clip_pytorch_model.bin" "$CLIP_TARGET"
else
    info "CLIP-ViT-H-14 already present — skipping."
fi

# ── 8. API workflow JSONs ─────────────────────────────────────────────────────
step "API workflow JSONs"
mkdir -p "$COMFYUI_PATH/API"
cp "$SCRIPT_DIR/td_integration/API/"*.json "$COMFYUI_PATH/API/"
info "Copied $(ls "$SCRIPT_DIR/td_integration/API/"*.json | wc -l | tr -d ' ') workflows to $COMFYUI_PATH/API/"

# ── 9. Desktop launcher ───────────────────────────────────────────────────────
step "Creating Desktop launcher"

LAUNCHER="$HOME/Desktop/Launch ComfyUI.command"

if [ "$INSTALL_TYPE" = "source" ]; then
    # Determine launch flags (same logic as start_comfy.sh)
    OS_TYPE="$(uname -s)"
    ARCH="$(uname -m)"
    if [[ "$OS_TYPE" == "Darwin" && "$ARCH" == "arm64" ]]; then
        LAUNCH_FLAGS="--preview-method none --dont-upcast-attention"
        LAUNCH_ENV="export PYTORCH_ENABLE_MPS_FALLBACK=1; export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0"
    elif command -v nvidia-smi &>/dev/null; then
        VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$VRAM_MB" ] && [ "$VRAM_MB" -ge 6000 ]; then
            LAUNCH_FLAGS="--preview-method none"
            LAUNCH_ENV=""
        else
            LAUNCH_FLAGS="--lowvram --preview-method none"
            LAUNCH_ENV=""
        fi
    else
        LAUNCH_FLAGS="--cpu --preview-method none"
        LAUNCH_ENV=""
    fi

    VENV_ACTIVATE="${COMFY_VENV:-$COMFYUI_PATH/venv}/bin/activate"

    cat > "$LAUNCHER" << LAUNCHERSCRIPT
#!/bin/bash
# Launch ComfyUI (source install)
echo "────────────────────────────────────────"
echo "  Starting ComfyUI..."
echo "  http://127.0.0.1:8188"
echo "────────────────────────────────────────"
${LAUNCH_ENV}
source "${VENV_ACTIVATE}"
python "${COMFYUI_PATH}/main.py" ${LAUNCH_FLAGS} --port 8188
LAUNCHERSCRIPT

else
    # Desktop app
    cat > "$LAUNCHER" << 'LAUNCHERSCRIPT'
#!/bin/bash
# Launch ComfyUI Desktop app and open the browser interface
echo "────────────────────────────────────────"
echo "  Launching ComfyUI..."
echo "  Will open http://127.0.0.1:8188 when ready"
echo "────────────────────────────────────────"

open -a ComfyUI 2>/dev/null || open -a "ComfyUI Desktop" 2>/dev/null || {
    echo "Could not find ComfyUI app. Open it manually from /Applications."
    exit 1
}

echo "Waiting for server to start..."
for i in $(seq 1 60); do
    if curl -s http://127.0.0.1:8188 >/dev/null 2>&1; then
        echo "Server ready!"
        open "http://127.0.0.1:8188"
        exit 0
    fi
    sleep 1
done
echo "Server did not respond in 60 s — open http://127.0.0.1:8188 manually."
LAUNCHERSCRIPT
fi

chmod +x "$LAUNCHER"
info "Desktop launcher created: ~/Desktop/Launch ComfyUI.command"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Setup complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  ComfyUI data folder : $COMFYUI_PATH"
echo "  Models downloaded   : checkpoints, loras, controlnet, ipadapter, clip_vision"
echo "  Custom nodes added  : ComfyUI-Manager, IPAdapter Plus, ControlNet Aux"
echo "  Workflows copied to : $COMFYUI_PATH/API/"
echo ""
if [ "$INSTALL_TYPE" = "desktop" ]; then
    echo -e "  ${YELLOW}NOTE (Desktop app):${NC} On first launch, ComfyUI Manager may prompt you to"
    echo "  install missing custom node requirements. Click 'Install' when prompted."
    echo ""
fi
echo "  Next steps:"
echo "  1. Double-click 'Launch ComfyUI' on your Desktop"
echo "  2. Open TouchDesigner: sd15_controlnet_comfyTOX.1.toe"
echo "  3. In the ComfyTD component (green box), press P → Setup page"
echo "  4. Set Basefolder to:"
echo "       $COMFYUI_PATH"
echo "  5. Go to Settings page → select a workflow from the API Workflow dropdown"
echo "  6. Press Generate"
echo ""
