#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/.env"

TAG="${DOCKER_IMAGE}:latest"

echo "Building $TAG ..."
docker build --build-arg HF_TOKEN="$HF_TOKEN" -t "$TAG" .

echo "Pushing $TAG ..."
docker push "$TAG"

echo "Done: $TAG"
