#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/.env"

JFK_URL="https://trascrivi-riunioni-upload.s3.eu-central-1.amazonaws.com/uploads/video1007492948.mp3?response-content-disposition=inline&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEBcaDGV1LWNlbnRyYWwtMSJHMEUCIEPCCA5kyrtgHpeYOoTd%2BK02UJNa7Yzo%2BZ0OEbP6wh5VAiEAtcPHY1XVBJY8yZBY8Jxk3To%2FxbKzPKb7YpJZozxvlGwqwgMI4P%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FARADGgw0Mzg5NDQzOTA3OTEiDL2%2FUxBhKZJ2m6mXJyqWA19ci0tI%2Bnaojh1XN4Nf5dYKrwUMhB%2BF2TCJIutetLpRQCvf0vQQyBMbIQK7uWpf29qes4OPjqHN4y%2F0NF41CwncAhGq74RSAtQSC0QYOxSBlJE03k1u%2B%2BLLiPEZjnNck1T403P%2FYIazrMOJAgEYQR6t5X3HLfrcDfAn4XoNVe19Hn2gum773z3ibFCTxxvsS1GN0H2KQbjBuJ%2BTP5HIHvxqAf3c5SzUcGvxCl3tX3ThlVc93upjWJBK1Zt3nQ5LbwkwPR%2BdnID0jjg8bf4kJrJLACoDfDAZe%2BFz7vboyxgYCEI%2FrJm9WQcsdHGZvM3QRLz91VtIrH%2FF4eW0czNIUlBp98jVbQDF0hmOCSLArUFUKiH7%2Fu%2BOorw%2B93%2FEQr5mvEcIk5y7Qno9ZHSqdPFhjezGctYCVK5DXFzSaoEo2p76BHURL76aQ3UkpX%2FAVifP2mla%2FwskO8u6kpWBUkpVrhCRXUI15d78ZaT4qYIfoY9eXVCDjL8FHVBUTjr0BOiG5Vpx2srba9lZsatfLxJWYum6Ftgif5Iw1vmpzQY63gKjSx5T4iphAM%2FwePFRc0JKK7z3qvVZ3YwZC2cIuzEsyFTZYKutC8vKBE3USsgu%2FGIVwZ0BY5uzd7stnvyVJ5ULzHJdC2EVTPzMoSC0uXLq63QMozvDSosDftouVRc6u4ZR99jix3QI3yw6ZeAaEyM0I4hhaFsW7%2Bl2ZtYu3qHimN%2ByP1C54Qun9fe3gwJoLpNM%2BmHGpppElXCvhAflDF94lSdhfze%2FVkmQZVb5346xd9Y6pks%2FDOFK5u8JXQo3KT%2Bv9%2FYj%2FuONya23MDPLxAETtvUBvjYokXHnLPHWXCePhvuuyrNVpeSpDm53MU9iqJAKO44h78gqECwJtztAz2F%2FF%2F%2Bd7quvlxq2jXns70DJtv8TJtIyTEPo55nfn9dGL6KP56VkHKs34cugqTnWNZF51xtqMZL1zdfGy56Ab97xzfAk2nP0JnxKr0Xzv7C0iMmZOMNNpAOMOcGsPTgkFQ%3D%3D&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=ASIAWMMY732DWB3PPJWU%2F20260306%2Feu-central-1%2Fs3%2Faws4_request&X-Amz-Date=20260306T070907Z&X-Amz-Expires=36000&X-Amz-SignedHeaders=host&X-Amz-Signature=2b44987c6136f698cf38681e29b6ff6223d5aae5163ca818516339460f9ae06c"

LANGUAGE="it"
BEAM_SIZE=5
VAD_FILTER=true
CONDITION_ON_PREVIOUS_TEXT=false
INITIAL_PROMPT=null
MIN_SPEAKERS=null
MAX_SPEAKERS=null
NUM_SPEAKERS=null

BASE_URL="https://api.runpod.ai/v2/$RUNPOD_ENDPOINT_ID"
RUNSYNC_WAIT_MS=300000
POLL_INTERVAL_SECONDS=5

PAYLOAD=$(jq -n \
  --arg audio_url "$JFK_URL" \
  --arg language "$LANGUAGE" \
  --argjson beam_size "$BEAM_SIZE" \
  --argjson vad_filter "$VAD_FILTER" \
  --argjson condition_on_previous_text "$CONDITION_ON_PREVIOUS_TEXT" \
  --argjson initial_prompt "$INITIAL_PROMPT" \
  --argjson min_speakers "$MIN_SPEAKERS" \
  --argjson max_speakers "$MAX_SPEAKERS" \
  --argjson num_speakers "$NUM_SPEAKERS" \
  '{
    input: {
      audio_url: $audio_url,
      language: $language,
      beam_size: $beam_size,
      vad_filter: $vad_filter,
      condition_on_previous_text: $condition_on_previous_text,
      initial_prompt: $initial_prompt,
      min_speakers: $min_speakers,
      max_speakers: $max_speakers,
      num_speakers: $num_speakers
    }
  }')

echo "Submitting job to endpoint $RUNPOD_ENDPOINT_ID ..."

INITIAL_RESPONSE=$(curl -s \
  -X POST \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$BASE_URL/runsync?wait=$RUNSYNC_WAIT_MS")

echo "$INITIAL_RESPONSE" | jq .

STATUS=$(echo "$INITIAL_RESPONSE" | jq -r '.status // empty')

if [[ "$STATUS" == "COMPLETED" ]]; then
  exit 0
fi

JOB_ID=$(echo "$INITIAL_RESPONSE" | jq -r '.id // empty')
if [[ -z "$JOB_ID" ]]; then
  echo "No job id returned by RunPod." >&2
  exit 1
fi

echo "Job $JOB_ID is $STATUS. Polling every ${POLL_INTERVAL_SECONDS}s..."

while true; do
  sleep "$POLL_INTERVAL_SECONDS"

  STATUS_RESPONSE=$(curl -s \
    -X GET \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    "$BASE_URL/status/$JOB_ID")

  echo "$STATUS_RESPONSE" | jq .

  STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status // empty')

  case "$STATUS" in
    COMPLETED)
      exit 0
      ;;
    FAILED|CANCELLED|TIMED_OUT)
      exit 1
      ;;
  esac
done
