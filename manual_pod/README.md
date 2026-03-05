# Manual Pod Validation — FastWhisper + Diarization

Goal: validate the full stack on a live RunPod GPU pod before building the serverless handler.
One step at a time. A step only gets written here after it's been validated live.

---

## KEY LEARNINGS FROM SESSION 1 (read before doing anything)

- **Container disk persists across restarts.** "Restart pod" does NOT wipe pip packages.
  Only terminating the pod and creating a new one resets the container to the base image.

- **Do NOT `pip install pyannote.audio` unversioned.** pyannote.audio 4.x requires
  `torch>=2.8`, which upgrades torch from 2.4.1 → 2.10.0, breaks torchvision, breaks
  torchaudio (torchcodec needs FFmpeg), changes the output API. Total mess.
  **Always pin: `pip install "pyannote.audio<4.0"`**

- **pyannote/speaker-diarization-3.1 was designed for pyannote.audio 3.x**, not 4.x.
  Using 3.x keeps torch 2.4.1 intact and uses soundfile (no FFmpeg needed).

- **SSH key must be Ed25519**, not RSA. RunPod's SSH proxy rejects old RSA signature algo.
  Generate with: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_runpod`

- **torchcodec warning is noise** if you're on pyannote 3.x — irrelevant.

- **HF_TOKEN env var must be set** before any pyannote step.
  `export HF_TOKEN=hf_your_token_here`

- **HF_HOME should point to /workspace** so models survive pod restarts.
  `export HF_HOME=/workspace/hf_cache`

- **pyannote models require accepting terms on HuggingFace** before download:
  - https://huggingface.co/pyannote/speaker-diarization-3.1
  - https://huggingface.co/pyannote/segmentation-3.0

---

## KEY LEARNINGS FROM SESSION 2

- **`huggingface_hub` must be pinned to `<0.20`** — pyannote 3.x internally calls
  `hf_hub_download(use_auth_token=...)` which was removed in huggingface_hub 0.20+.

- **`hf_transfer` must be installed** — RunPod sets `HF_HUB_ENABLE_HF_TRANSFER=1` by default,
  so if the package is missing it errors out. `pip install hf_transfer`.

- **`Pipeline.from_pretrained()` does NOT accept `token=` or `use_auth_token=` kwargs**
  in pyannote 3.4.0. Just set `HF_TOKEN` env var — it is picked up automatically.

- **`Pipeline.from_pretrained()` does NOT accept local paths**, only HF repo IDs.

- **Install everything at once** to avoid partial state on a fresh pod:
  `pip install faster-whisper "pyannote.audio<4.0" "huggingface_hub<0.20" hf_transfer`

---

## STEP 0 — Create the pod (validated)

**Custom template** in RunPod (not a pre-built one — need full port control).

**Image:** `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`

| Setting | Value |
|---|---|
| GPU | RTX 4000 Ada (20 GB VRAM) — or A40 |
| Container disk | 20 GB |
| Volume disk | 50 GB |
| Volume mount path | `/workspace` |
| Expose TCP | 22 (SSH) |
| Expose HTTP | 8000 (for later) |

SSH key: use Ed25519 key added in RunPod account settings.

```bash
ssh <pod-id>@ssh.runpod.io -i ~/.ssh/id_ed25519_runpod
```

---

## STEP 1 — Verify GPU and environment (validated)

```bash
nvidia-smi
python --version && python -c "import torch; print(torch.__version__); print(torch.cuda.is_available())"
```

Expected:
- GPU visible, CUDA 12.4
- Python 3.11.x
- PyTorch 2.4.x+cu124
- True

---

## STEP 2 — Install faster-whisper (validated)

```bash
pip install faster-whisper
python -c "import faster_whisper; print(faster_whisper.__version__)"
```

Result: `1.2.1`

---

## STEP 3 — Download Whisper model and test transcription (validated)

```bash
export HF_HOME=/workspace/hf_cache
wget -O /tmp/test.wav "https://github.com/ggerganov/whisper.cpp/raw/master/samples/jfk.wav"
python -c "
from faster_whisper import WhisperModel
model = WhisperModel('large-v3', device='cuda', compute_type='float16')
segments, info = model.transcribe('/tmp/test.wav', beam_size=5)
for seg in segments:
    print(f'[{seg.start:.1f}s -> {seg.end:.1f}s] {seg.text}')
"
```

Result:
```
[0.0s -> 10.4s]  And so, my fellow Americans, ask not what your country can do for you, ask what you can do for your country.
```

---

## STEP 4 — Install pyannote.audio 3.x and test diarization (validated)

Install everything at once with version pins:

```bash
pip install faster-whisper "pyannote.audio<4.0" "huggingface_hub<0.20" hf_transfer
```

Verify torch is still 2.4.x:

```bash
python -c "import torch; print(torch.__version__)"
```

Expected: `2.4.x+cu124`

Load pipeline and run diarization on test file:

```bash
python -c "
import torch
from pyannote.audio import Pipeline
pipeline = Pipeline.from_pretrained('pyannote/speaker-diarization-3.1')
pipeline.to(torch.device('cuda'))
diarization = pipeline('/tmp/test.wav')
for turn, _, speaker in diarization.itertracks(yield_label=True):
    print(f'[{turn.start:.1f}s -> {turn.end:.1f}s] {speaker}')
"
```

Result:
```
[0.3s -> 2.2s] SPEAKER_00
[3.3s -> 3.8s] SPEAKER_00
[3.9s -> 4.4s] SPEAKER_00
[5.4s -> 7.6s] SPEAKER_00
[8.1s -> 10.5s] SPEAKER_00
```

---

## STEP 5 — Combined transcription + diarization (validated)

```bash
python -c "
import torch
from faster_whisper import WhisperModel
from pyannote.audio import Pipeline

whisper = WhisperModel('large-v3', device='cuda', compute_type='float16')
diarizer = Pipeline.from_pretrained('pyannote/speaker-diarization-3.1')
diarizer.to(torch.device('cuda'))

audio_file = '/tmp/test.wav'

segments, info = whisper.transcribe(audio_file, beam_size=5)
segments = list(segments)

diarization = diarizer(audio_file)

def get_speaker(start, end, diarization):
    best, best_dur = 'UNKNOWN', 0
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        overlap = min(end, turn.end) - max(start, turn.start)
        if overlap > best_dur:
            best, best_dur = speaker, overlap
    return best

for seg in segments:
    speaker = get_speaker(seg.start, seg.end, diarization)
    print(f'[{seg.start:.1f}s -> {seg.end:.1f}s] {speaker}: {seg.text.strip()}')
"
```

Result:
```
[0.0s -> 10.4s] SPEAKER_00: And so, my fellow Americans, ask not what your country can do for you, ask what you can do for your country.
```

---

## STEP 6 — (next: build the RunPod serverless handler)
