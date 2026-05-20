# ReduxStation TTS gateway.
#
# Hosts Piper VITS+ONNX on CPU and exposes the HTTP contract that SStts in the
# game container expects. en_GB-vctk-medium (109 speakers) and en_US-libritts_r-medium
# (904 speakers) ship together for ~1013 voices total. Voice models are downloaded at
# build time so the resulting image is self-contained.
#
# Phase 1 scope: pure Piper inference, opus output, no ffmpeg filter chain yet.
# Phases 3 and later layer radio click splicing, silicon convolution, and rubberband
# pitch shift on top.

FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ffmpeg \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Pin requirements first for layer caching.
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Voice catalog files (mapping + ONNX downloads).
COPY voice_mapping.json /app/voice_mapping.json
COPY download_voices.sh /app/download_voices.sh
RUN bash /app/download_voices.sh /app/voices

# Application code last so iterative edits do not bust the heavy layers.
COPY app.py /app/app.py

ENV TTS_AUTHORIZATION_TOKEN=coolio \
    TTS_BIND_HOST=0.0.0.0 \
    TTS_BIND_PORT=5500 \
    TTS_VOICES_DIR=/app/voices

EXPOSE 5500

HEALTHCHECK --interval=5s --timeout=2s --start-period=30s --retries=3 \
    CMD curl -fsS "http://localhost:${TTS_BIND_PORT}/health-check" || exit 1

CMD ["python", "-u", "app.py"]
