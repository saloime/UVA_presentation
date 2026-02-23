#!/bin/bash
# =============================================================================
# download_models.sh — ComfyUI model downloader (wget, RunPod-compatible)
#
# Works in two contexts:
#   A) runpod/comfyui:latest  — run this directly in the pod terminal
#   B) Custom Docker build    — called by start.sh on container boot
#
# USAGE:
#   bash download_models.sh
#   HF_TOKEN=hf_xxx bash download_models.sh        # skip the prompt
#   COMFYUI_DIR=/my/path bash download_models.sh   # custom install path
#
# MODELS DOWNLOADED:
#   Stable Diffusion 1.5
#   Stable Diffusion XL + VAE
#   FLUX.1-dev + text encoders + VAE  [HF_TOKEN required]
#   FLUX.2 Klein 4B fp8
#   FLUX.2 Klein 9B fp8
#   Qwen Image (base generation) fp8
#   Qwen Image Edit 2509 fp8
# =============================================================================
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
COMFYUI_DIR="${COMFYUI_DIR:-/workspace/ComfyUI}"
MODELS="$COMFYUI_DIR/models"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; NC="\033[0m"
info()  { echo -e "${CYAN}  $*${NC}"; }
ok()    { echo -e "${GREEN}  ✓  $*${NC}"; }
warn()  { echo -e "${YELLOW}  ⚠  $*${NC}"; }
err()   { echo -e "${RED}  ✗  $*${NC}"; }

# ── Check wget ────────────────────────────────────────────────────────────────
if ! command -v wget &>/dev/null; then
    echo "wget not found — installing..."
    apt-get install -y wget 2>/dev/null || { err "Please install wget and re-run."; exit 1; }
fi

# ── HuggingFace token ─────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ComfyUI Model Downloader"
echo "  Destination: $MODELS"
echo "══════════════════════════════════════════════════════════════"
echo ""

if [ -z "${HF_TOKEN:-}" ]; then
    echo "  Some models (FLUX.1-dev) require a HuggingFace token."
    echo "  Get yours at: https://huggingface.co/settings/tokens"
    echo "  You must also accept the license at:"
    echo "  https://huggingface.co/black-forest-labs/FLUX.1-dev"
    echo ""
    read -rsp "  Enter HuggingFace token (Enter to skip gated models): " HF_TOKEN
    echo ""
fi

[ -z "${HF_TOKEN:-}" ] && warn "No token — FLUX.1-dev will be skipped." || ok "HF token set."
echo ""

# ── Download helper ───────────────────────────────────────────────────────────
# dl <dest_path> <url> [auth]
#   dest_path : full path where file is saved
#   url       : direct HuggingFace resolve URL
#   auth      : "true" to send Authorization header (default: false)
dl() {
    local dest="$1"
    local url="$2"
    local auth="${3:-false}"
    local name
    name="$(basename "$dest")"

    if [ -f "$dest" ]; then
        ok "$name  (already exists)"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"

    if [ "$auth" = "true" ] && [ -z "${HF_TOKEN:-}" ]; then
        warn "Skipped $name  (no HF token)"
        return 1
    fi

    info "Downloading $name ..."

    local wget_args=(-q --show-progress -c -L -O "$dest")
    if [ "$auth" = "true" ]; then
        wget_args+=(--header="Authorization: Bearer $HF_TOKEN")
    fi

    if wget "${wget_args[@]}" "$url"; then
        ok "$name  done  ($(du -sh "$dest" | cut -f1))"
    else
        err "$name  FAILED"
        rm -f "$dest"
        return 1
    fi
}

# Convenience: HuggingFace public URL
hf()  { echo "https://huggingface.co/$1/resolve/main/$2"; }

# ── Create model directories ──────────────────────────────────────────────────
mkdir -p "$MODELS/"{checkpoints,diffusion_models,text_encoders,vae,loras,controlnet,clip_vision}

# =============================================================================
#  STABLE DIFFUSION 1.5
#  checkpoints/
# =============================================================================
echo "── Stable Diffusion 1.5 ─────────────────────────────────────"

dl  "$MODELS/checkpoints/v1-5-pruned-emaonly.safetensors" \
    "$(hf stable-diffusion-v1-5/stable-diffusion-v1-5 v1-5-pruned-emaonly.safetensors)"

# =============================================================================
#  STABLE DIFFUSION XL
#  checkpoints/   vae/
# =============================================================================
echo ""
echo "── Stable Diffusion XL ──────────────────────────────────────"

dl  "$MODELS/checkpoints/sd_xl_base_1.0.safetensors" \
    "$(hf stabilityai/stable-diffusion-xl-base-1.0 sd_xl_base_1.0.safetensors)"

# fp16-fixed VAE prevents washed-out colors with SDXL
dl  "$MODELS/vae/sdxl_vae.safetensors" \
    "$(hf madebyollin/sdxl-vae-fp16-fix sdxl_vae.safetensors)"

# =============================================================================
#  FLUX.1-dev — text encoders + VAE (public, no token needed)
#  text_encoders/   vae/
#
#  clip_l + t5xxl are also used if you load FLUX.1-dev via the
#  DualCLIPLoader node in ComfyUI.
# =============================================================================
echo ""
echo "── FLUX.1 — shared text encoders + VAE (public) ─────────────"

dl  "$MODELS/text_encoders/clip_l.safetensors" \
    "$(hf comfyanonymous/flux_text_encoders clip_l.safetensors)"

dl  "$MODELS/text_encoders/t5xxl_fp8_e4m3fn.safetensors" \
    "$(hf comfyanonymous/flux_text_encoders t5xxl_fp8_e4m3fn.safetensors)"

# ae.safetensors = FLUX VAE, lives in FLUX.1-schnell (Apache 2.0 — no auth)
dl  "$MODELS/vae/flux1-ae.safetensors" \
    "$(hf black-forest-labs/FLUX.1-schnell ae.safetensors)"

# =============================================================================
#  FLUX.1-dev — diffusion model  *** GATED — requires HF_TOKEN ***
#
#  Before downloading you MUST accept the license at:
#  https://huggingface.co/black-forest-labs/FLUX.1-dev
#
#  diffusion_models/
# =============================================================================
echo ""
echo "── FLUX.1-dev — diffusion model (gated) ─────────────────────"

dl  "$MODELS/diffusion_models/flux1-dev.safetensors" \
    "$(hf black-forest-labs/FLUX.1-dev flux1-dev.safetensors)" \
    "true"

# =============================================================================
#  FLUX.2 Klein — shared VAE
#  Both 4B and 9B use the same flux2-vae — downloaded once here.
#  vae/
# =============================================================================
echo ""
echo "── FLUX.2 Klein — shared VAE ────────────────────────────────"

dl  "$MODELS/vae/flux2-vae.safetensors" \
    "$(hf Comfy-Org/vae-text-encorder-for-flux-klein-4b split_files/vae/flux2-vae.safetensors)"

# =============================================================================
#  FLUX.2 Klein 4B (fp8)
#  text_encoders/   diffusion_models/
#
#  In ComfyUI: DiffusionModelLoader → flux-2-klein-4b-fp8.safetensors
#              CLIPLoader (type: flux) → qwen_3_4b.safetensors
#              VAELoader → flux2-vae.safetensors
# =============================================================================
echo ""
echo "── FLUX.2 Klein 4B fp8 ──────────────────────────────────────"

dl  "$MODELS/text_encoders/qwen_3_4b.safetensors" \
    "$(hf Comfy-Org/vae-text-encorder-for-flux-klein-4b split_files/text_encoders/qwen_3_4b.safetensors)"

dl  "$MODELS/diffusion_models/flux-2-klein-4b-fp8.safetensors" \
    "$(hf black-forest-labs/FLUX.2-klein-4b-fp8 flux-2-klein-4b-fp8.safetensors)"

# =============================================================================
#  FLUX.2 Klein 9B (fp8)
#  text_encoders/   diffusion_models/
#
#  In ComfyUI: DiffusionModelLoader → flux-2-klein-9b-fp8.safetensors
#              CLIPLoader (type: flux) → qwen_3_8b_fp8mixed.safetensors
#              VAELoader → flux2-vae.safetensors  (shared)
# =============================================================================
echo ""
echo "── FLUX.2 Klein 9B fp8 ──────────────────────────────────────"

dl  "$MODELS/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
    "$(hf Comfy-Org/vae-text-encorder-for-flux-klein-9b split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors)"

dl  "$MODELS/diffusion_models/flux-2-klein-9b-fp8.safetensors" \
    "$(hf black-forest-labs/FLUX.2-klein-9b-fp8 flux-2-klein-9b-fp8.safetensors)"

# =============================================================================
#  QWEN IMAGE — base generation (fp8)
#  diffusion_models/   text_encoders/   vae/
#
#  The VAE and text encoder are shared with Qwen Image Edit 2509.
#  In ComfyUI: use native Qwen Image workflow nodes.
# =============================================================================
echo ""
echo "── Qwen Image — shared VAE + text encoder ───────────────────"

dl  "$MODELS/vae/qwen_image_vae.safetensors" \
    "$(hf Comfy-Org/Qwen-Image_ComfyUI split_files/vae/qwen_image_vae.safetensors)"

dl  "$MODELS/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
    "$(hf Comfy-Org/Qwen-Image_ComfyUI split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors)"

echo ""
echo "── Qwen Image — base generation model ───────────────────────"

dl  "$MODELS/diffusion_models/qwen_image_fp8_e4m3fn.safetensors" \
    "$(hf Comfy-Org/Qwen-Image_ComfyUI split_files/diffusion_models/qwen_image_fp8_e4m3fn.safetensors)"

# =============================================================================
#  QWEN IMAGE EDIT 2509 (fp8)
#  diffusion_models/
#
#  VAE + text encoder shared with Qwen Image — already downloaded above.
#  Supports: single-image edit, multi-image compositing, ControlNet
#  (keypoint/sketch), product posters, person consistency.
# =============================================================================
echo ""
echo "── Qwen Image Edit 2509 ─────────────────────────────────────"

dl  "$MODELS/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors" \
    "$(hf Comfy-Org/Qwen-Image-Edit_ComfyUI split_files/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors)"

# =============================================================================
#  Summary
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Done. Files on disk:"
echo "══════════════════════════════════════════════════════════════"
find "$MODELS" -name "*.safetensors" -o -name "*.bin" | sort | while read -r f; do
    size=$(du -sh "$f" | cut -f1)
    rel="${f#"$MODELS/"}"
    printf "  %-72s %s\n" "$rel" "$size"
done
echo ""
echo "  Restart or refresh ComfyUI to load new models."
echo "  Open: http://localhost:8188"
echo ""
