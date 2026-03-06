#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/.env"

JFK_URL="https://github.com/ggerganov/whisper.cpp/raw/master/samples/jfk.wav"

echo "Submitting job to endpoint $RUNPOD_ENDPOINT_ID ..."

curl -s \
  -X POST \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"input\": {\"audio_url\": \"$JFK_URL\"}}" \
  "https://api.runpod.io/v2/$RUNPOD_ENDPOINT_ID/runsync" \
| jq .
