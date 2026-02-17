#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# start_comfy.sh — Launch ComfyUI with settings optimised for your hardware
#
# Detects your platform automatically.
# You can override the mode by setting COMFY_MODE before running:
#
#   COMFY_MODE=lowvram  bash start_comfy.sh    # NVIDIA GPU < 6 GB VRAM
#   COMFY_MODE=cpu      bash start_comfy.sh    # No GPU / Intel Mac
#   COMFY_MODE=mps      bash start_comfy.sh    # Apple Silicon (default on M-series)
#   COMFY_MODE=gpu      bash start_comfy.sh    # NVIDIA GPU with plenty of VRAM
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Activate venv ─────────────────────────────────────────────────────────────
source "$SCRIPT_DIR/venv/bin/activate"

# ── Auto-detect mode if not overridden ───────────────────────────────────────
if [ -z "$COMFY_MODE" ]; then
    OS_TYPE="$(uname -s)"
    ARCH="$(uname -m)"
    if [[ "$OS_TYPE" == "Darwin" && "$ARCH" == "arm64" ]]; then
        COMFY_MODE="mps"
    elif command -v nvidia-smi &>/dev/null; then
        # Check available VRAM
        VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$VRAM_MB" ] && [ "$VRAM_MB" -ge 6000 ]; then
            COMFY_MODE="gpu"
        else
            COMFY_MODE="lowvram"
        fi
    else
        COMFY_MODE="cpu"
    fi
fi

# ── Build launch flags based on mode ─────────────────────────────────────────
case "$COMFY_MODE" in
    mps)
        echo "────────────────────────────────────────────"
        echo "  ComfyUI  |  Apple Silicon  |  MPS backend"
        echo "  http://127.0.0.1:8188"
        echo "────────────────────────────────────────────"
        export PYTORCH_ENABLE_MPS_FALLBACK=1
        export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
        EXTRA_FLAGS="--preview-method none --dont-upcast-attention"
        ;;
    gpu)
        echo "────────────────────────────────────────────"
        echo "  ComfyUI  |  NVIDIA GPU  |  CUDA backend"
        echo "  http://127.0.0.1:8188"
        echo "────────────────────────────────────────────"
        EXTRA_FLAGS="--preview-method none"
        ;;
    lowvram)
        echo "────────────────────────────────────────────"
        echo "  ComfyUI  |  NVIDIA (low VRAM)  |  CUDA"
        echo "  http://127.0.0.1:8188"
        echo "  Note: generation will be slower in low-VRAM mode"
        echo "────────────────────────────────────────────"
        EXTRA_FLAGS="--lowvram --preview-method none"
        ;;
    cpu)
        echo "────────────────────────────────────────────"
        echo "  ComfyUI  |  CPU-only mode"
        echo "  http://127.0.0.1:8188"
        echo "  Warning: generation will take 2–5 min per image"
        echo "────────────────────────────────────────────"
        EXTRA_FLAGS="--cpu --preview-method none"
        ;;
esac

python "$SCRIPT_DIR/ComfyUI/main.py" \
    $EXTRA_FLAGS \
    --port 8188
