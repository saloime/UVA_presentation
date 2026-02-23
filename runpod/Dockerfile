FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        wget \
        curl \
        aria2 \
        libgl1-mesa-glx \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Clone ComfyUI (latest) ────────────────────────────────────────────────────
RUN git clone https://github.com/comfyanonymous/ComfyUI /opt/ComfyUI

# ── Install ComfyUI Python requirements ──────────────────────────────────────
RUN pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt

# ── Install huggingface_hub for model downloads ───────────────────────────────
RUN pip install --no-cache-dir "huggingface_hub[cli]>=0.26.0"

# ── Install ComfyUI Manager ───────────────────────────────────────────────────
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
        /opt/ComfyUI/custom_nodes/ComfyUI-Manager \
    && pip install --no-cache-dir \
        -r /opt/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt

# ── Copy startup + download scripts ──────────────────────────────────────────
COPY scripts/start.sh          /scripts/start.sh
COPY scripts/download_models.py /scripts/download_models.py
RUN chmod +x /scripts/start.sh

# ── Pre-create model directories (workspace volume may be mounted later) ──────
RUN mkdir -p /opt/ComfyUI/models/{checkpoints,diffusion_models,text_encoders,vae,loras,controlnet,upscale_models,clip_vision}

# ── Expose ComfyUI port ───────────────────────────────────────────────────────
EXPOSE 8188

# ── Entrypoint ────────────────────────────────────────────────────────────────
ENTRYPOINT ["/scripts/start.sh"]
