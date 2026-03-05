FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

ARG HF_TOKEN

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Download models at build time so cold starts don't need network access
ENV HF_HOME=/app/hf_cache
RUN HF_TOKEN=$HF_TOKEN python -c "\
from faster_whisper import WhisperModel; \
WhisperModel('large-v3', device='cpu', compute_type='int8'); \
from pyannote.audio import Pipeline; \
Pipeline.from_pretrained('pyannote/speaker-diarization-3.1')"

COPY handler.py .

ENV HF_HOME=/app/hf_cache
CMD ["python", "-u", "handler.py"]
