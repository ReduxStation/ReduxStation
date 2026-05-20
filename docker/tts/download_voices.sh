#!/usr/bin/env bash
# Download Piper voice models at image build time. Pulls from the official Hugging
# Face mirror at rhasspy/piper-voices. Each voice ships as an .onnx and a .onnx.json
# config file; we need both.
#
# Models bundled by default:
#   en_GB-vctk-medium      109 UK English VCTK speakers (the "comical" tg-style sound)
#   en_US-libritts_r-medium 904 American English LibriTTS-R speakers (raw variety)
#
# Together they give us ~1013 voices for ~125 MB of disk.

set -euo pipefail

DEST="${1:-/app/voices}"
mkdir -p "${DEST}"

BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main"

download_voice() {
    local relpath="$1"
    local fname
    fname="$(basename "${relpath}")"
    echo "Fetching ${fname}"
    curl -fsSL -o "${DEST}/${fname}" "${BASE}/${relpath}"
    curl -fsSL -o "${DEST}/${fname}.json" "${BASE}/${relpath}.json"
}

download_voice "en/en_GB/vctk/medium/en_GB-vctk-medium.onnx"
download_voice "en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx"

echo "Voice catalog populated under ${DEST}:"
ls -lh "${DEST}"
