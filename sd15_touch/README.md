# sd15_touch — Real-Time AI Image Generation

TouchDesigner + ComfyUI + Stable Diffusion 1.5 on Apple Silicon.

Generates AI images live from TouchDesigner frames using LCM (2–4 step inference), ControlNet for edge/depth guidance, and dual IP-Adapters for style reference.

---

## Requirements

| | Minimum | Recommended |
|---|---|---|
| **OS** | macOS 12+ or Windows 10/11 | macOS with Apple Silicon |
| **RAM** | 16 GB | 32 GB+ |
| **GPU** | None (CPU-only, slow) | Apple Silicon / NVIDIA 6 GB+ VRAM |
| **Disk** | 12 GB free | 20 GB free |
| **Python** | 3.10 | 3.11 |

**Required software (all free):**
- **Python 3.10–3.12** — [python.org/downloads](https://www.python.org/downloads/)
- **Git**
  - macOS: `xcode-select --install` in Terminal
  - Windows: [git-scm.com](https://git-scm.com) — includes Git Bash
- **TouchDesigner** (free non-commercial licence) — [derivative.ca](https://derivative.ca)

---

## Installation

### macOS
Open **Terminal** and run:
```bash
git clone https://github.com/saloime/UVA_presentation.git
cd UVA_presentation/sd15_touch
bash setup.sh
```

### Windows
Open **Git Bash** (installed with Git for Windows — right-click your desktop → "Git Bash Here") and run:
```bash
git clone https://github.com/saloime/UVA_presentation.git
cd UVA_presentation/sd15_touch
bash setup.sh
```

> **Windows note:** If `bash` isn't found, open Git Bash from your Start menu and navigate to the folder manually:
> `cd ~/Desktop/UVA_presentation/sd15_touch && bash setup.sh`

`setup.sh` automatically:
1. Clones ComfyUI
2. Creates a Python virtual environment and installs all dependencies (**detects your GPU automatically**)
3. Clones required ComfyUI custom nodes
4. Downloads all model weights (~7 GB)
5. Creates the internal `ComfyUI/API` symlink

> **First run takes 20–40 minutes** (downloading ~7 GB of models).
> If interrupted, just re-run `bash setup.sh` — it skips already-downloaded files.

---

## Running

### 1. Start ComfyUI

```bash
cd sd15_touch
bash start_comfy.sh
```

`start_comfy.sh` **automatically detects your hardware** and applies the right settings:

| Hardware | Mode | Speed |
|----------|------|-------|
| Apple M1/M2/M3/M4 | MPS | ~1–4 s/image |
| NVIDIA GPU ≥ 6 GB VRAM | CUDA | ~2–8 s/image |
| NVIDIA GPU < 6 GB VRAM | CUDA low-VRAM | ~10–30 s/image |
| No GPU / Intel Mac | CPU | ~2–5 min/image |

You can also force a specific mode:
```bash
COMFY_MODE=lowvram bash start_comfy.sh   # force low-VRAM NVIDIA mode
COMFY_MODE=cpu     bash start_comfy.sh   # force CPU mode
```

Wait for `To see the GUI go to: http://127.0.0.1:8188` in the terminal. Leave this running.

### 2. Open TouchDesigner

Open `sd15_controlnet_comfyTOX.toe`.

### 3. Configure ComfyTD

In the **ComfyTD** component (the green box in the network):

1. Press `P` to open parameters
2. Go to the **Setup** page
3. Set **Basefolder** to the absolute path of your `sd15_touch/ComfyUI/` folder
   - Example: `/Users/yourname/Desktop/UVA_presentation/sd15_touch/ComfyUI`
4. Go to the **Settings** page — select a workflow from the **API Workflow** dropdown
   - `workflow_lcm.json` → fast text-to-image (no camera input needed)
   - `workflow_controlnet_ipadapter.json` → full pipeline with live video input
5. Press **Generate** to run your first generation

> **Tip:** If the workflow dropdown is blank, make sure ComfyUI is running (step 1) before loading the TOX — it reads node information from the live server.

---

## What's in this repo

```
sd15_touch/
├── setup.sh                        ← run this first
├── start_comfy.sh                  ← start ComfyUI server
├── sd15_controlnet_comfyTOX.toe    ← TouchDesigner project file
├── td_integration/
│   ├── API/                        ← ComfyUI API workflow JSONs
│   │   ├── workflow_lcm.json
│   │   └── workflow_controlnet_ipadapter.json
│   ├── ComfyTD-0.2.5.tox           ← TouchDesigner ComfyUI component
│   └── custom_nodes/
│       └── websocket_image_save.py ← custom ComfyUI node (copied to ComfyUI by setup.sh)
└── ComfyUI/                        ← cloned by setup.sh (not in git)
    └── models/                     ← downloaded by setup.sh (not in git)
```

---

## Workflows

### `workflow_lcm.json` — Text to Image
No camera required. Type a prompt, press Generate. Uses LCM LoRA for ~2 step (~1.4 s) inference.

### `workflow_controlnet_ipadapter.json` — Live Video to Image
Full pipeline:
- **TD Input Frame** → ControlNet (Canny edge or MiDaS Depth) → guides image structure
- **IP-Adapter 1 + 2** → style reference images → guides visual appearance
- **Prompt** → guides content

Parameters exposed in ComfyTD's Config page:
| Parameter | What it does |
|-----------|-------------|
| Positive Prompt | Describe what you want |
| TD Input Frame | TOP to use as ControlNet + img2img source |
| IP-Adapter 1/2 Image | TOPs for style reference |
| ControlNet strength | 0 = ignore structure, 1 = follow exactly |
| IP-Adapter weight | 0 = ignore style, 1 = copy style exactly |
| Denoise | 0.5 = stays close to input, 1.0 = full generation |

---

## Models installed by setup.sh

| Model | Size | Purpose |
|-------|------|---------|
| SD 1.5 (`v1-5-pruned-emaonly`) | ~4 GB | Base diffusion model |
| LCM LoRA | ~400 MB | Enables 2–4 step inference |
| ControlNet Canny | ~700 MB | Edge-based structure guidance |
| ControlNet Depth | ~700 MB | Depth-map structure guidance |
| IP-Adapter Plus SD1.5 | ~800 MB | Style transfer from reference images |
| CLIP ViT-H/14 | ~3.9 GB | Vision encoder (required by IP-Adapter) |

---

## Performance by Hardware

### Apple Silicon (M1/M2/M3/M4)
Works out of the box — the fastest experience. 512×512 at 4 LCM steps runs in 1–4 seconds.

### NVIDIA GPU (Windows / Linux)
Works with CUDA. Tested on RTX 3060 and above. For GPUs with less than 6 GB VRAM, `start_comfy.sh` will automatically use `--lowvram` mode, which keeps the model on CPU RAM and only moves what's needed to the GPU for each step. Slower but functional.

### No GPU / Intel Mac / Low-End Laptop
CPU-only mode works but is slow — expect 2–5 minutes per image. You can still test the full pipeline, just with longer waits. Consider using `workflow_lcm.json` (2 steps) instead of the full ControlNet workflow while on CPU.

---

## Troubleshooting

**Workflow dropdown is blank in ComfyTD**
→ ComfyUI must be running before you load/open the TOX. Start `start_comfy.sh` first.

**Black / grey output images**
→ This is an Apple Silicon fp16 issue. The `start_comfy.sh` script is already configured correctly (`--fp32-vae` behaviour is built into the MPS path). If you see black images, try restarting ComfyUI.

**`ClipVision model not found` error in ComfyUI**
→ The CLIP model filename must start with `CLIP-ViT-H-14`. `setup.sh` handles this rename automatically.

**`generate_from_top() error` or nothing happens on button press**
→ Check that ComfyUI is running at `http://127.0.0.1:8188` and the WebSocket DAT shows "Connected".

**Module not found / Python errors in TouchDesigner**
→ Use absolute operator paths. Instead of `op('name')`, use `op('/project1/name')`.

---

## Credits

- **ComfyUI** — [github.com/comfyanonymous/ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- **ComfyTD v0.2.5** — dotsimulate ([patreon.com/posts/122745633](https://www.patreon.com/posts/122745633/))
- **IPAdapter Plus** — cubiq ([github.com/cubiq/ComfyUI_IPAdapter_plus](https://github.com/cubiq/ComfyUI_IPAdapter_plus))
- **ControlNet preprocessors** — Fannovel16 ([github.com/Fannovel16/comfyui_controlnet_aux](https://github.com/Fannovel16/comfyui_controlnet_aux))
