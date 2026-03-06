import os
import subprocess
import time
import uuid

import requests
import runpod
import torch
from faster_whisper import WhisperModel
from pyannote.audio import Pipeline

# Models loaded once per worker — warm invocations skip this
print("Loading Whisper large-v3...")
whisper = WhisperModel("large-v3", device="cuda", compute_type="float16")

print("Loading pyannote speaker-diarization-3.1...")
diarizer = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
diarizer.to(torch.device("cuda"))

print("Models ready.")


def format_hhmmss(seconds):
    total_seconds = max(0, int(round(seconds)))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def get_speaker(start, end, diarization):
    best, best_dur = "UNKNOWN", 0
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        overlap = min(end, turn.end) - max(start, turn.start)
        if overlap > best_dur:
            best, best_dur = speaker, overlap
    return best


def handler(job):
    inp = job["input"]

    audio_url = inp["audio_url"]
    language = inp.get("language", None)
    beam_size = inp.get("beam_size", 5)
    vad_filter = inp.get("vad_filter", True)
    condition_on_previous_text = inp.get("condition_on_previous_text", False)
    initial_prompt = inp.get("initial_prompt", None)
    min_speakers = inp.get("min_speakers", None)
    max_speakers = inp.get("max_speakers", None)
    num_speakers = inp.get("num_speakers", None)

    job_id = str(uuid.uuid4())[:8]
    input_path = f"/tmp/{job_id}_input"
    wav_path = f"/tmp/{job_id}.wav"

    try:
        t_start = time.time()

        # Download audio
        response = requests.get(audio_url, stream=True, timeout=300)
        response.raise_for_status()
        with open(input_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=65536):
                f.write(chunk)

        # Convert to 16kHz mono WAV
        t_ffmpeg = time.time()
        subprocess.run(
            ["ffmpeg", "-y", "-i", input_path, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav_path],
            check=True,
            capture_output=True,
        )
        t_ffmpeg_done = time.time()

        # Transcribe
        t_whisper = time.time()
        segments, info = whisper.transcribe(
            wav_path,
            beam_size=beam_size,
            language=language,
            vad_filter=vad_filter,
            word_timestamps=True,
            condition_on_previous_text=condition_on_previous_text,
            initial_prompt=initial_prompt,
        )
        segments = list(segments)
        t_whisper_done = time.time()

        # Diarize
        diarize_kwargs = {}
        if num_speakers:
            diarize_kwargs["num_speakers"] = num_speakers
        else:
            if min_speakers:
                diarize_kwargs["min_speakers"] = min_speakers
            if max_speakers:
                diarize_kwargs["max_speakers"] = max_speakers

        t_diarize = time.time()
        diarization = diarizer(wav_path, **diarize_kwargs)
        t_diarize_done = time.time()

        # Merge transcription + diarization
        all_speakers = set()
        out_segments = []

        for seg in segments:
            seg_speaker = get_speaker(seg.start, seg.end, diarization)
            all_speakers.add(seg_speaker)

            words = []
            for w in (seg.words or []):
                w_speaker = get_speaker(w.start, w.end, diarization)
                all_speakers.add(w_speaker)
                words.append({
                    "word": w.word,
                    "start": round(w.start, 3),
                    "end": round(w.end, 3),
                    "speaker": w_speaker,
                })

            out_segments.append({
                "start": round(seg.start, 3),
                "end": round(seg.end, 3),
                "speaker": seg_speaker,
                "text": seg.text.strip(),
                "words": words,
            })

        real_speakers = sorted(s for s in all_speakers if s != "UNKNOWN")

        t_total = time.time() - t_start
        t_ff = t_ffmpeg_done - t_ffmpeg
        t_w = t_whisper_done - t_whisper
        t_d = t_diarize_done - t_diarize
        speed = info.duration / t_total if t_total else 0

        print(
            f"[stats] audio={format_hhmmss(info.duration)} | "
            f"ffmpeg={format_hhmmss(t_ff)} | "
            f"whisper={format_hhmmss(t_w)} | "
            f"diarize={format_hhmmss(t_d)} | "
            f"total={format_hhmmss(t_total)} | "
            f"speed={speed:.2f}x realtime"
        )

        return {
            "language": info.language,
            "duration": round(info.duration, 3),
            "num_speakers": len(real_speakers),
            "speakers": real_speakers,
            "segments": out_segments,
        }

    finally:
        if os.path.exists(input_path):
            os.unlink(input_path)
        if os.path.exists(wav_path):
            os.unlink(wav_path)


runpod.serverless.start({"handler": handler})
