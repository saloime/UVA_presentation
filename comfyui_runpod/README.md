# ComfyUI on RunPod — Setup Guide

Two ways to run ComfyUI on RunPod with all models pre-loaded:

| | Option A — RunPod image | Option B — Custom Docker build |
|---|---|---|
| **Effort** | Low — start pod + run one script | Higher — build & push your own image |
| **Best for** | Quick experiments, single user | Reproducible, shareable deployments |
| **Image** | `runpod/comfyui:latest` | Your Docker Hub image |
| **Models** | Downloaded at runtime via `download_models.sh` | Downloaded at runtime via `download_models.sh` |

---

## Models included

| Model | Files | Approx size | ComfyUI folder |
|-------|-------|-------------|----------------|
| Stable Diffusion 1.5 | `v1-5-pruned-emaonly.safetensors` | 4 GB | `checkpoints/` |
| SDXL base | `sd_xl_base_1.0.safetensors` | 7 GB | `checkpoints/` |
| SDXL VAE (fp16 fix) | `sdxl_vae.safetensors` | 0.3 GB | `vae/` |
| FLUX.1-dev ⚠️ | `flux1-dev.safetensors` | 24 GB | `diffusion_models/` |
| FLUX.1 text encoders | `clip_l.safetensors` + `t5xxl_fp8_e4m3fn.safetensors` | 0.8 GB | `text_encoders/` |
| FLUX.1 VAE | `flux1-ae.safetensors` | 0.3 GB | `vae/` |
| FLUX.2 Klein shared VAE | `flux2-vae.safetensors` | 0.3 GB | `vae/` |
| FLUX.2 Klein 4B fp8 | `flux-2-klein-4b-fp8.safetensors` | 8 GB | `diffusion_models/` |
| FLUX.2 Klein 4B text enc | `qwen_3_4b.safetensors` | 2 GB | `text_encoders/` |
| FLUX.2 Klein 9B fp8 | `flux-2-klein-9b-fp8.safetensors` | 18 GB | `diffusion_models/` |
| FLUX.2 Klein 9B text enc | `qwen_3_8b_fp8mixed.safetensors` | 8 GB | `text_encoders/` |
| Qwen Image fp8 | `qwen_image_fp8_e4m3fn.safetensors` | 20 GB | `diffusion_models/` |
| Qwen Image VAE | `qwen_image_vae.safetensors` | 0.5 GB | `vae/` |
| Qwen Image text enc | `qwen_2.5_vl_7b_fp8_scaled.safetensors` | 7 GB | `text_encoders/` |
| Qwen Image Edit 2509 fp8 | `qwen_image_edit_2509_fp8_e4m3fn.safetensors` | 20 GB | `diffusion_models/` |

> **Total: ~120 GB.** Files already on disk are always skipped — downloads only happen once per network volume.

> ⚠️ **FLUX.1-dev is gated.** You must accept the license at [huggingface.co/black-forest-labs/FLUX.1-dev](https://huggingface.co/black-forest-labs/FLUX.1-dev) and supply a HuggingFace token. All other models are Apache 2.0 or similar open licenses.

---

## Option A — Using `runpod/comfyui:latest`

### 1. Create a RunPod pod

1. Go to [runpod.io](https://runpod.io) → **Pods** → **Deploy**
2. Choose a GPU — recommended:
   - **FLUX.2 Klein 4B** — RTX 3090 / RTX 4080 (16–24 GB VRAM)
   - **FLUX.2 Klein 9B** — RTX 4090 / A6000 (24–48 GB VRAM)
   - **Full stack** — A100 80 GB for everything at once
3. Set **Container Image** to: `runpod/comfyui:latest`
4. Add a **Network Volume** (at least 150 GB) mounted at `/workspace`
   — models persist here; you only download once
5. Click **Deploy**

### 2. Open the terminal

In your pod dashboard click **Connect → Terminal** (or JupyterLab → Terminal).

### 3. Run the download script

Copy `scripts/download_models.sh` to the pod, or paste it directly:

```bash
# Option 1 — clone this repo
cd /workspace
git clone https://github.com/saloime/UVA_presentation.git
bash UVA_presentation/comfyui_runpod/scripts/download_models.sh

# Option 2 — pass your token inline (skips the prompt)
HF_TOKEN=hf_xxxxxxxxxxxx bash download_models.sh
```

The script will:
- Prompt for your HuggingFace token (or read it from `HF_TOKEN`)
- Download all models to `/workspace/ComfyUI/models/`
- Skip any files that already exist
- Print a summary when done

### 4. Open ComfyUI

RunPod exposes port **8188** via its proxy. Click **Connect → HTTP Service → 8188** in your pod dashboard.

---

## Option B — Custom Docker build

Use this if you want a fully reproducible image you can push to Docker Hub and share as a RunPod template.

### Prerequisites

- Docker installed locally
- Docker Hub account (free at [hub.docker.com](https://hub.docker.com))

### 1. Build the image

```bash
cd comfyui_runpod/

docker build -t your-dockerhub-username/comfyui-runpod:latest .
```

The image includes:
- `runpod/pytorch:2.4.0-py3.11-cuda12.4.1` base
- ComfyUI (latest source)
- ComfyUI Manager
- `download_models.sh` + `start.sh` bundled

### 2. Push to Docker Hub

```bash
docker login
docker push your-dockerhub-username/comfyui-runpod:latest
```

### 3. Create a RunPod template

1. RunPod → **Templates** → **New Template**
2. Set **Container Image** to your Docker Hub tag
3. Set **Container Disk**: 20 GB (code only — models go on network volume)
4. Add **Environment Variables**:

| Variable | Value | Notes |
|----------|-------|-------|
| `HF_TOKEN` | `hf_xxxx` | Required for FLUX.1-dev |
| `COMFYUI_ARGS` | *(optional)* | Extra flags for `main.py` |

5. **Expose HTTP Port**: `8188`
6. Save template

### 4. Deploy a pod from your template

1. **Pods** → **Deploy** → select your template
2. Mount a **Network Volume** at `/workspace` (150 GB+)
3. Deploy — on first boot `start.sh` runs, downloads all models, then starts ComfyUI

On every subsequent start, existing model files are skipped — the pod is ready in seconds.

---

## ComfyUI model node setup

Once models are downloaded, load them in ComfyUI using these node types:

### FLUX.1-dev
```
DualCLIPLoader    → clip_l.safetensors + t5xxl_fp8_e4m3fn.safetensors  (type: flux)
DiffusionModelLoader → flux1-dev.safetensors
VAELoader         → flux1-ae.safetensors
```

### FLUX.2 Klein 4B / 9B
```
CLIPLoader        → qwen_3_4b.safetensors   OR   qwen_3_8b_fp8mixed.safetensors
DiffusionModelLoader → flux-2-klein-4b-fp8.safetensors   OR   flux-2-klein-9b-fp8.safetensors
VAELoader         → flux2-vae.safetensors
```

### SD 1.5 / SDXL
```
Load Checkpoint   → v1-5-pruned-emaonly.safetensors   OR   sd_xl_base_1.0.safetensors
VAELoader         → sdxl_vae.safetensors  (SDXL only — improves color accuracy)
```

### Qwen Image / Qwen Image Edit 2509
```
DiffusionModelLoader → qwen_image_fp8_e4m3fn.safetensors
                   OR  qwen_image_edit_2509_fp8_e4m3fn.safetensors
CLIPLoader        → qwen_2.5_vl_7b_fp8_scaled.safetensors
VAELoader         → qwen_image_vae.safetensors
```
Workflow examples: [docs.comfy.org/tutorials/image/qwen/qwen-image](https://docs.comfy.org/tutorials/image/qwen/qwen-image)

---

## File structure

```
comfyui_runpod/
├── Dockerfile                  ← custom build (Option B)
├── README.md                   ← this file
└── scripts/
    ├── download_models.sh      ← wget-based downloader (works in any context)
    └── start.sh                ← container entrypoint (Option B)
```

---

## Troubleshooting

**Download fails with 401 / 403**
→ FLUX.1-dev requires a token. Accept the license at the HF page and set `HF_TOKEN`.

**Download fails with 404**
→ The model filename in the BFL repository may have changed. Check the file listing at:
`https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8/tree/main`

**Out of disk space**
→ Increase your network volume size. 150 GB covers the full model set.

**ComfyUI shows "model not found"**
→ Verify the file exists: `ls /workspace/ComfyUI/models/diffusion_models/`
→ Refresh the ComfyUI model list: **Settings → Refresh Models**

**FLUX.2 Klein model is slow**
→ Make sure `--fp8_e4m3fn-unet` is passed to `main.py` (already set in `start.sh`).
