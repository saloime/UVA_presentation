#!/usr/bin/env python3
"""
Download all ComfyUI models for RunPod deployment.

Models downloaded:
  - Stable Diffusion 1.5
  - Stable Diffusion XL (base + VAE)
  - FLUX.1-dev  [requires HF_TOKEN + license agreement at hf.co/black-forest-labs/FLUX.1-dev]
  - FLUX.2 Klein 4B (fp8)
  - FLUX.2 Klein 9B (fp8)
  - Qwen Image (base generation, fp8)
  - Qwen Image Edit 2509 (fp8)

Shared files are downloaded once and reused across models:
  - FLUX.1 text encoders (clip_l + t5xxl_fp8)  → used by FLUX.1-dev
  - FLUX.2 VAE (flux2-vae)                     → shared by Klein 4B + 9B
  - Qwen VAE + text encoder                    → shared by Qwen Image + Edit

Environment variables:
  COMFYUI_DIR   Path to ComfyUI root  (default: /workspace/ComfyUI)
  HF_TOKEN      HuggingFace access token — required for FLUX.1-dev
"""

import os
import sys
import shutil
from pathlib import Path

# ── huggingface_hub ────────────────────────────────────────────────────────────
try:
    from huggingface_hub import hf_hub_download, login, HfApi
except ImportError:
    print("Installing huggingface_hub…")
    os.system("pip install -q 'huggingface_hub[cli]>=0.26.0'")
    from huggingface_hub import hf_hub_download, login, HfApi

# ── Config ─────────────────────────────────────────────────────────────────────
COMFYUI_DIR = Path(os.environ.get("COMFYUI_DIR", "/workspace/ComfyUI"))
HF_TOKEN    = os.environ.get("HF_TOKEN") or None

MODELS = COMFYUI_DIR / "models"

if HF_TOKEN:
    login(token=HF_TOKEN, add_to_git_credential=False)
    print("✓ Logged in to HuggingFace")
else:
    print("ℹ  HF_TOKEN not set — gated models (FLUX.1-dev) will be skipped")

# ── Helper ─────────────────────────────────────────────────────────────────────
def dl(repo_id: str, hf_path: str, dest_dir: Path, dest_name: str | None = None):
    """Download one file from HuggingFace if not already present."""
    name = dest_name or hf_path.rsplit("/", 1)[-1]
    dest = dest_dir / name

    if dest.exists():
        print(f"  ✓  {name}")
        return True

    dest_dir.mkdir(parents=True, exist_ok=True)
    print(f"  ↓  {name}  ←  {repo_id}/{hf_path}")

    try:
        cached = hf_hub_download(
            repo_id=repo_id,
            filename=hf_path,
            token=HF_TOKEN,
        )
        shutil.copy2(cached, dest)
        print(f"  ✓  {name} done ({dest.stat().st_size / 1e9:.1f} GB)")
        return True
    except Exception as exc:
        print(f"  ✗  {name} FAILED: {exc}")
        if dest.exists():
            dest.unlink()
        return False


def section(title: str):
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


# ══════════════════════════════════════════════════════════════════════════════
#  STABLE DIFFUSION 1.5
#  Checkpoint: models/checkpoints/
# ══════════════════════════════════════════════════════════════════════════════
section("Stable Diffusion 1.5")

dl(
    repo_id   = "stable-diffusion-v1-5/stable-diffusion-v1-5",
    hf_path   = "v1-5-pruned-emaonly.safetensors",
    dest_dir  = MODELS / "checkpoints",
)


# ══════════════════════════════════════════════════════════════════════════════
#  STABLE DIFFUSION XL
#  Checkpoint: models/checkpoints/
#  VAE:        models/vae/
# ══════════════════════════════════════════════════════════════════════════════
section("Stable Diffusion XL")

dl(
    repo_id   = "stabilityai/stable-diffusion-xl-base-1.0",
    hf_path   = "sd_xl_base_1.0.safetensors",
    dest_dir  = MODELS / "checkpoints",
)

# fp16-fixed VAE prevents the washed-out color issue with SDXL
dl(
    repo_id   = "madebyollin/sdxl-vae-fp16-fix",
    hf_path   = "sdxl_vae.safetensors",
    dest_dir  = MODELS / "vae",
)


# ══════════════════════════════════════════════════════════════════════════════
#  FLUX.1-dev
#
#  ⚠  Requires: HF_TOKEN + license accepted at
#     https://huggingface.co/black-forest-labs/FLUX.1-dev
#
#  Text encoders  → models/text_encoders/
#  VAE            → models/vae/
#  Diffusion model→ models/diffusion_models/
# ══════════════════════════════════════════════════════════════════════════════
section("FLUX.1-dev — shared text encoders + VAE")

# clip_l and t5xxl are also used by FLUX.2 Klein — download once here
dl(
    repo_id   = "comfyanonymous/flux_text_encoders",
    hf_path   = "clip_l.safetensors",
    dest_dir  = MODELS / "text_encoders",
)

dl(
    repo_id   = "comfyanonymous/flux_text_encoders",
    hf_path   = "t5xxl_fp8_e4m3fn.safetensors",
    dest_dir  = MODELS / "text_encoders",
)

# ae.safetensors is the FLUX VAE — from FLUX.1-schnell (Apache 2.0, no auth needed)
dl(
    repo_id   = "black-forest-labs/FLUX.1-schnell",
    hf_path   = "ae.safetensors",
    dest_dir  = MODELS / "vae",
    dest_name = "flux1-ae.safetensors",
)

section("FLUX.1-dev — diffusion model (gated)")

if HF_TOKEN:
    dl(
        repo_id   = "black-forest-labs/FLUX.1-dev",
        hf_path   = "flux1-dev.safetensors",
        dest_dir  = MODELS / "diffusion_models",
    )
else:
    print("  ⚠  Skipped — set HF_TOKEN and accept license at:")
    print("     https://huggingface.co/black-forest-labs/FLUX.1-dev")


# ══════════════════════════════════════════════════════════════════════════════
#  FLUX.2 Klein — shared VAE
#  The Klein VAE (flux2-vae) is different from the FLUX.1 ae.safetensors.
#  Both 4B and 9B share this VAE file.
# ══════════════════════════════════════════════════════════════════════════════
section("FLUX.2 Klein — shared VAE")

# Comfy-Org packages the VAE alongside the Klein 4B text encoder
dl(
    repo_id   = "Comfy-Org/vae-text-encorder-for-flux-klein-4b",
    hf_path   = "split_files/vae/flux2-vae.safetensors",
    dest_dir  = MODELS / "vae",
    dest_name = "flux2-vae.safetensors",
)


# ══════════════════════════════════════════════════════════════════════════════
#  FLUX.2 Klein 4B (fp8)
#
#  Text encoder   → models/text_encoders/   (Qwen3 4B)
#  Diffusion model→ models/diffusion_models/
#  VAE            → already downloaded above
#
#  ComfyUI nodes: DiffusionModelLoader + CLIPLoader (qwen3_4b) + VAELoader
#  In ComfyUI set:  CLIP type = "flux" when loading clip_l + t5xxl
#                   CLIP type = "wan"  when loading the Qwen3 text encoder
# ══════════════════════════════════════════════════════════════════════════════
section("FLUX.2 Klein 4B")

dl(
    repo_id   = "Comfy-Org/vae-text-encorder-for-flux-klein-4b",
    hf_path   = "split_files/text_encoders/qwen_3_4b.safetensors",
    dest_dir  = MODELS / "text_encoders",
    dest_name = "qwen_3_4b.safetensors",
)

# FP8 unified model (text-to-image + image editing + multi-reference)
dl(
    repo_id   = "black-forest-labs/FLUX.2-klein-4b-fp8",
    hf_path   = "flux-2-klein-4b-fp8.safetensors",
    dest_dir  = MODELS / "diffusion_models",
)


# ══════════════════════════════════════════════════════════════════════════════
#  FLUX.2 Klein 9B (fp8)
#
#  Text encoder   → models/text_encoders/   (Qwen3 8B)
#  Diffusion model→ models/diffusion_models/
#  VAE            → flux2-vae.safetensors (already downloaded)
# ══════════════════════════════════════════════════════════════════════════════
section("FLUX.2 Klein 9B")

dl(
    repo_id   = "Comfy-Org/vae-text-encorder-for-flux-klein-9b",
    hf_path   = "split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors",
    dest_dir  = MODELS / "text_encoders",
    dest_name = "qwen_3_8b_fp8mixed.safetensors",
)

# FP8 unified model (text-to-image + image editing + multi-reference)
dl(
    repo_id   = "black-forest-labs/FLUX.2-klein-9b-fp8",
    hf_path   = "flux-2-klein-9b-fp8.safetensors",
    dest_dir  = MODELS / "diffusion_models",
)


# ══════════════════════════════════════════════════════════════════════════════
#  QWEN IMAGE (base generation)
#
#  Diffusion model→ models/diffusion_models/
#  VAE            → models/vae/
#  Text encoder   → models/text_encoders/   (Qwen2.5-VL 7B fp8)
#
#  The VAE and text encoder are shared with Qwen Image Edit 2509.
# ══════════════════════════════════════════════════════════════════════════════
section("Qwen Image — shared VAE + text encoder")

dl(
    repo_id   = "Comfy-Org/Qwen-Image_ComfyUI",
    hf_path   = "split_files/vae/qwen_image_vae.safetensors",
    dest_dir  = MODELS / "vae",
    dest_name = "qwen_image_vae.safetensors",
)

dl(
    repo_id   = "Comfy-Org/Qwen-Image_ComfyUI",
    hf_path   = "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors",
    dest_dir  = MODELS / "text_encoders",
    dest_name = "qwen_2.5_vl_7b_fp8_scaled.safetensors",
)

section("Qwen Image — base generation model")

dl(
    repo_id   = "Comfy-Org/Qwen-Image_ComfyUI",
    hf_path   = "split_files/diffusion_models/qwen_image_fp8_e4m3fn.safetensors",
    dest_dir  = MODELS / "diffusion_models",
    dest_name = "qwen_image_fp8_e4m3fn.safetensors",
)


# ══════════════════════════════════════════════════════════════════════════════
#  QWEN IMAGE EDIT 2509
#
#  Diffusion model→ models/diffusion_models/
#  VAE            → qwen_image_vae.safetensors  (already downloaded)
#  Text encoder   → qwen_2.5_vl_7b_fp8_scaled  (already downloaded)
#
#  Supports: single-image edit, multi-image compositing, ControlNet (keypoint,
#  sketch), product posters, person consistency.
# ══════════════════════════════════════════════════════════════════════════════
section("Qwen Image Edit 2509")

dl(
    repo_id   = "Comfy-Org/Qwen-Image-Edit_ComfyUI",
    hf_path   = "split_files/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors",
    dest_dir  = MODELS / "diffusion_models",
    dest_name = "qwen_image_edit_2509_fp8_e4m3fn.safetensors",
)


# ══════════════════════════════════════════════════════════════════════════════
#  Summary
# ══════════════════════════════════════════════════════════════════════════════
print(f"\n{'═' * 60}")
print("  Download complete. Model inventory:")
print(f"{'═' * 60}")
for subdir in sorted(MODELS.iterdir()):
    files = [f for f in subdir.iterdir() if f.suffix in {".safetensors", ".bin", ".pt"}]
    if files:
        print(f"\n  {subdir.name}/")
        for f in sorted(files):
            size_gb = f.stat().st_size / 1e9
            print(f"    {f.name:60s}  {size_gb:5.1f} GB")

print(f"\n  ComfyUI root: {COMFYUI_DIR}")
print("  Start ComfyUI and open http://localhost:8188\n")
