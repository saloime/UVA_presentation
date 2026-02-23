FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        wget \
        curl \
        libgl1-mesa-glx \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Clone ComfyUI ─────────────────────────────────────────────────────────────
RUN git clone https://github.com/comfyanonymous/ComfyUI /opt/ComfyUI

# ── Python requirements ───────────────────────────────────────────────────────
RUN pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt

# ── ComfyUI Manager ───────────────────────────────────────────────────────────
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
        /opt/ComfyUI/custom_nodes/ComfyUI-Manager \
    && pip install --no-cache-dir \
        -r /opt/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt

# ── Scripts ───────────────────────────────────────────────────────────────────
COPY scripts/start.sh           /scripts/start.sh
COPY scripts/download_models.sh /scripts/download_models.sh
RUN chmod +x /scripts/start.sh /scripts/download_models.sh

# ── Pre-create model directories ──────────────────────────────────────────────
RUN mkdir -p /opt/ComfyUI/models/{checkpoints,diffusion_models,text_encoders,vae,loras,controlnet,clip_vision}

EXPOSE 8188

ENTRYPOINT ["/scripts/start.sh"]
