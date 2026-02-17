#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# setup.sh — one-click install for sd15_touch
#
#   1. Clone ComfyUI
#   2. Create Python venv + install all requirements
#   3. Clone custom nodes + install their requirements
#   4. Copy the bundled WebSocket image node
#   5. Download all required model weights (~7 GB total)
#   6. Create the ComfyUI/API symlink
#
# Usage:
#   cd sd15_touch
#   bash setup.sh
#
# Requires: Python 3.10+, git, ~10 GB free disk space
# ─────────────────────────────────────────────────────────────────────────────

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}▶${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
error() { echo -e "${RED}✖${NC}  $*"; exit 1; }
step()  { echo -e "\n${BOLD}── $* ────────────────────────────────────────────────────────────${NC}"; }

# ── Prereq check ─────────────────────────────────────────────────────────────
step "Checking prerequisites"
command -v python3 >/dev/null || error "python3 not found. Install Python 3.10+ first."
command -v git     >/dev/null || error "git not found."
PY_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)")
[ "$PY_MINOR" -ge 10 ] || error "Python 3.10+ required (found 3.${PY_MINOR})."
info "python3 OK  |  git OK"

# ── 1. Clone ComfyUI ──────────────────────────────────────────────────────────
step "ComfyUI"
if [ ! -d "$SCRIPT_DIR/ComfyUI/.git" ]; then
    info "Cloning ComfyUI (shallow, latest stable)…"
    git clone https://github.com/comfyanonymous/ComfyUI.git \
        "$SCRIPT_DIR/ComfyUI" --depth 1
else
    info "ComfyUI already present — skipping clone."
fi

# ── 2. Python venv + requirements ────────────────────────────────────────────
step "Python environment"
if [ ! -d "$SCRIPT_DIR/venv" ]; then
    info "Creating venv…"
    python3 -m venv "$SCRIPT_DIR/venv"
fi
source "$SCRIPT_DIR/venv/bin/activate"

info "Upgrading pip…"
pip install --upgrade pip --quiet

info "Detecting platform for PyTorch install…"
OS_TYPE="$(uname -s)"
ARCH="$(uname -m)"
if [[ "$OS_TYPE" == "Darwin" && "$ARCH" == "arm64" ]]; then
    info "Apple Silicon detected → MPS backend"
    pip install torch torchvision torchaudio --quiet
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    info "Intel Mac detected → CPU backend (slow but works)"
    pip install torch torchvision torchaudio --quiet
elif command -v nvidia-smi &>/dev/null; then
    info "NVIDIA GPU detected → CUDA backend"
    pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu121 --quiet
else
    warn "No GPU detected → CPU-only mode (generation will be slow, ~2–5 min/image)"
    pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cpu --quiet
fi

info "Installing ComfyUI requirements…"
pip install -r "$SCRIPT_DIR/ComfyUI/requirements.txt" --quiet

info "Installing huggingface_hub (for model downloads)…"
pip install huggingface_hub --quiet

# ── 3. Custom nodes ───────────────────────────────────────────────────────────
step "Custom nodes"
CUSTOM_NODES="$SCRIPT_DIR/ComfyUI/custom_nodes"

if [ ! -d "$CUSTOM_NODES/ComfyUI_IPAdapter_plus" ]; then
    info "Cloning ComfyUI_IPAdapter_plus…"
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git \
        "$CUSTOM_NODES/ComfyUI_IPAdapter_plus" --depth 1
else
    info "ComfyUI_IPAdapter_plus already present."
fi
pip install -r "$CUSTOM_NODES/ComfyUI_IPAdapter_plus/requirements.txt" --quiet

if [ ! -d "$CUSTOM_NODES/comfyui_controlnet_aux" ]; then
    info "Cloning comfyui_controlnet_aux…"
    git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git \
        "$CUSTOM_NODES/comfyui_controlnet_aux" --depth 1
else
    info "comfyui_controlnet_aux already present."
fi
pip install -r "$CUSTOM_NODES/comfyui_controlnet_aux/requirements.txt" --quiet

# ── 4. WebSocket image node ───────────────────────────────────────────────────
info "Copying WebSocket image node…"
cp "$SCRIPT_DIR/td_integration/custom_nodes/websocket_image_save.py" \
   "$CUSTOM_NODES/websocket_image_save.py"

# ── 5. Model weights ──────────────────────────────────────────────────────────
step "Model downloads (~7 GB — this will take a while)"

CKPT="$SCRIPT_DIR/ComfyUI/models/checkpoints"
LORA="$SCRIPT_DIR/ComfyUI/models/loras"
CNET="$SCRIPT_DIR/ComfyUI/models/controlnet"
IPAD="$SCRIPT_DIR/ComfyUI/models/ipadapter"
CLIP="$SCRIPT_DIR/ComfyUI/models/clip_vision"

# Helper: download only if not already present
download_if_missing() {
    local dest="$1"; local repo="$2"; local file="$3"; local dir="$4"
    if [ ! -f "$dest" ]; then
        info "Downloading $(basename $dest)…"
        huggingface-cli download "$repo" "$file" --local-dir "$dir" \
            --local-dir-use-symlinks False
    else
        info "$(basename $dest) already present — skipping."
    fi
}

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
CLIP_TARGET="$CLIP/CLIP-ViT-H-14-laion2B-s32B-b79K.bin"
if [ ! -f "$CLIP_TARGET" ]; then
    info "Downloading CLIP-ViT-H-14 (~3.9 GB)…"
    huggingface-cli download "laion/CLIP-ViT-H-14-laion2B-s32B-b79K" \
        "open_clip_pytorch_model.bin" \
        --local-dir "$CLIP" \
        --local-dir-use-symlinks False
    # Rename to match IPAdapter's filename pattern
    mv "$CLIP/open_clip_pytorch_model.bin" "$CLIP_TARGET"
else
    info "CLIP-ViT-H-14 already present — skipping."
fi

# ── 6. API symlink ────────────────────────────────────────────────────────────
step "ComfyUI/API symlink"
rm -rf "$SCRIPT_DIR/ComfyUI/API"
ln -s ../td_integration/API "$SCRIPT_DIR/ComfyUI/API"
info "ComfyUI/API → $(readlink $SCRIPT_DIR/ComfyUI/API)"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Setup complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo "  1. Start ComfyUI:      bash start_comfy.sh"
echo "  2. Open TouchDesigner: sd15_controlnet_comfyTOX.toe"
echo "  3. In ComfyTD, set Basefolder to:  $(pwd)/ComfyUI"
echo "  4. Select a workflow from the API Workflow dropdown"
echo ""
