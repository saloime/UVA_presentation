#!/bin/bash
# =============================================================================
# start.sh — entrypoint for custom Docker build
#
# On every container start:
#   1. Copies /opt/ComfyUI → /workspace/ComfyUI (first boot only)
#      Models persist on RunPod's Network Volume across pod restarts.
#   2. Runs download_models.sh (skips files already on disk)
#   3. Launches ComfyUI on 0.0.0.0:8188
#
# Environment variables:
#   HF_TOKEN       HuggingFace token (required for FLUX.1-dev)
#   COMFYUI_ARGS   Extra args forwarded to main.py
# =============================================================================
set -euo pipefail

export COMFYUI_DIR="${COMFYUI_DIR:-/workspace/ComfyUI}"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ComfyUI — RunPod startup"
echo "  COMFYUI_DIR = $COMFYUI_DIR"
echo "══════════════════════════════════════════════════════════════"

# ── 1. Copy ComfyUI to persistent workspace (first boot only) ─────────────────
if [ ! -f "$COMFYUI_DIR/main.py" ]; then
    echo ""
    echo "[ 1/3 ] First boot — copying ComfyUI to workspace..."
    cp -r /opt/ComfyUI "$COMFYUI_DIR"
fi

mkdir -p "$COMFYUI_DIR/models/"{checkpoints,diffusion_models,text_encoders,vae,loras,controlnet,clip_vision}

# ── 2. Download models ────────────────────────────────────────────────────────
echo ""
echo "[ 2/3 ] Checking models (existing files skipped)..."
echo ""
bash /scripts/download_models.sh

# ── 3. Launch ComfyUI ─────────────────────────────────────────────────────────
echo ""
echo "[ 3/3 ] Starting ComfyUI..."
echo "        Open: http://0.0.0.0:8188  (or the RunPod proxy URL)"
echo ""

cd "$COMFYUI_DIR"

exec python3 main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    --fp8_e4m3fn-unet \
    ${COMFYUI_ARGS:-}
