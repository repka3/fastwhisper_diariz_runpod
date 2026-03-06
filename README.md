# Serverless Handler — FastWhisper + Diarization

RunPod serverless endpoint for transcription with speaker diarization and word-level timestamps.
Designed for long-form audio (meetings, interviews).

---

## Use cases

| Use case | Fits this endpoint? |
|---|---|
| Meeting transcription | YES — primary use case |
| Subtitle generation | YES — word-level timestamps included |
| Interview transcription | YES |
| Real-time voice assistant | NO — use a streaming/WebSocket service instead |

---

## Request schema

```json
{
  "input": {
    "audio_url": "https://...",

    "language":       "en",
    "beam_size":      5,
    "vad_filter":     true,
    "initial_prompt": null,
    "min_speakers":   null,
    "max_speakers":   null,
    "num_speakers":   null
  }
}
```

### Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `audio_url` | string | **required** | Publicly accessible URL to the audio file |
| `language` | string \| null | `null` | ISO 639-1 code (`"en"`, `"it"`, etc.). `null` = auto-detect |
| `beam_size` | int | `5` | Whisper beam size. Lower = faster, slightly less accurate |
| `vad_filter` | bool | `true` | Filter non-speech segments before transcription. Reduces hallucinations |
| `initial_prompt` | string \| null | `null` | Domain-specific context for Whisper (jargon, acronyms, names). E.g. `"EBITDA, KPI, Salesforce"` |
| `min_speakers` | int \| null | `null` | Minimum expected speakers. Set if known — improves diarization accuracy |
| `max_speakers` | int \| null | `null` | Maximum expected speakers. Set if known |
| `num_speakers` | int \| null | `null` | Exact speaker count. Overrides min/max if set |

---

## Response schema

```json
{
  "language": "en",
  "duration": 3612.4,
  "num_speakers": 2,
  "speakers": ["SPEAKER_00", "SPEAKER_01"],
  "segments": [
    {
      "start": 0.0,
      "end": 8.4,
      "speaker": "SPEAKER_00",
      "text": "Good morning everyone, let's get started.",
      "words": [
        { "word": "Good",      "start": 0.0, "end": 0.4, "speaker": "SPEAKER_00" },
        { "word": "morning",   "start": 0.4, "end": 0.9, "speaker": "SPEAKER_00" },
        { "word": "everyone,", "start": 0.9, "end": 1.5, "speaker": "SPEAKER_00" },
        { "word": "let's",     "start": 2.1, "end": 2.4, "speaker": "SPEAKER_00" },
        { "word": "get",       "start": 2.4, "end": 2.6, "speaker": "SPEAKER_00" },
        { "word": "started.",  "start": 2.6, "end": 3.1, "speaker": "SPEAKER_00" }
      ]
    },
    {
      "start": 9.0,
      "end": 14.2,
      "speaker": "SPEAKER_01",
      "text": "Thanks, I'll share my screen.",
      "words": [...]
    }
  ]
}
```

### Notes on the response

- **`segments`** — whisper segments, each assigned to the speaker with the most overlap.
  Use this for a readable transcript or chat-bubble UI.

- **`words`** — every word with its own timestamp and speaker.
  Use this for subtitle rendering (SRT/VTT generation) or precise speaker boundaries.

- **Segment speaker vs word speaker** — they can differ at speaker boundaries.
  For subtitles, use word-level speakers. For a clean transcript, use segment-level.

- **`UNKNOWN`** — a word/segment gets this speaker if it falls entirely outside any
  diarized region (e.g. music, noise that VAD didn't filter). Not counted in `num_speakers`.

---

## Error response

```json
{
  "error": "description of what went wrong"
}
```

---

## Supported audio formats

Whatever `ffmpeg` can decode: mp3, mp4, m4a, wav, ogg, flac, webm, etc.
All input is converted to 16kHz mono WAV before processing.

---

## Notes on long audio

- Models are loaded once at container startup (warm workers reuse them — no reload cost).
- For a 1-hour meeting expect ~2-4 min processing time on an RTX 4000 Ada.
- Audio is downloaded from `audio_url` to `/tmp` before processing. Make sure the URL
  is publicly accessible or pre-signed for the duration of the job.

---

## Deployment

### Build and push

Models are baked into the image at build time — no network access needed at runtime.
`HF_TOKEN` is passed as a build arg (never stored in the image layer):

```bash
docker build --build-arg HF_TOKEN=hf_xxx -t your-registry/fastwhisper-diariz:latest .
docker push your-registry/fastwhisper-diariz:latest
```

`HF_HUB_ENABLE_HF_TRANSFER=1` is set inside the Dockerfile so fast downloads are active during the build. No action needed from you.
