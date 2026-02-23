#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# RunPod container entrypoint
#
# What this does on every container start:
#   1. Copies ComfyUI from /opt/ComfyUI to /workspace/ComfyUI if not present
#      (so models persist on RunPod's network volume across pod restarts)
#   2. Creates all required model subdirectories
#   3. Runs download_models.py — skips files that already exist
#   4. Launches ComfyUI on 0.0.0.0:8188
#
# Environment variables:
#   HF_TOKEN       HuggingFace token (required for FLUX.1-dev)
#   COMFYUI_ARGS   Extra args passed to main.py  (optional)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

COMFYUI_DIR="${COMFYUI_DIR:-/workspace/ComfyUI}"
export COMFYUI_DIR

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ComfyUI — RunPod startup"
echo "  COMFYUI_DIR = $COMFYUI_DIR"
echo "══════════════════════════════════════════════════════════════"

# ── 1. Install ComfyUI into workspace (persists across restarts) ───────────
if [ ! -f "$COMFYUI_DIR/main.py" ]; then
    echo ""
    echo "[ 1/3 ] Copying ComfyUI to workspace volume..."
    cp -r /opt/ComfyUI "$COMFYUI_DIR"
    echo "        Done."
else
    echo ""
    echo "[ 1/3 ] ComfyUI already in workspace — skipping copy."
fi

# ── 2. Ensure model directories exist ──────────────────────────────────────
echo ""
echo "[ 2/3 ] Creating model directories..."
mkdir -p "$COMFYUI_DIR/models/"{checkpoints,diffusion_models,text_encoders,vae,loras,controlnet,clip_vision,upscale_models}

# ── 3. Download models ──────────────────────────────────────────────────────
echo ""
echo "[ 3/3 ] Checking / downloading models..."
echo "        (Files already on disk are skipped.)"
echo "        Total fresh download: ~100 GB — this only happens once."
echo ""

python3 /scripts/download_models.py

# ── 4. Launch ComfyUI ───────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Launching ComfyUI at http://0.0.0.0:8188"
echo "  RunPod proxy URL shown in your pod dashboard."
echo "══════════════════════════════════════════════════════════════"
echo ""

cd "$COMFYUI_DIR"

# Detect GPU capabilities for best flags
EXTRA_ARGS="${COMFYUI_ARGS:-}"

# fp8_e4m3fn for UNets reduces VRAM without quality loss on CUDA
EXTRA_ARGS="$EXTRA_ARGS --fp8_e4m3fn-unet"

exec python3 main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    $EXTRA_ARGS
