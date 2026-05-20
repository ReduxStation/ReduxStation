# ReduxStation TTS gateway

Self-hosted TTS service backing SStts in the game container. Wraps Piper (VITS+ONNX
on CPU) behind an aiohttp gateway and exposes the HTTP contract the DM-side
subsystem expects.

## What it does in Phase 1

- Hosts 2 Piper voice models: `en_GB-vctk-medium` (109 UK English speakers, the
  "comical" tg sound) and `en_US-libritts_r-medium` (904 American LibriTTS-R
  speakers for raw variety). ~1013 voices total.
- Implements `GET /tts-voices`, `GET /pitch-available`, `GET /tts`,
  `GET /tts-blips`, `GET /health-check` matching the API contract SStts uses.
- Returns ogg/vorbis audio with an `audio-length: HH:MM:SS.fff` header.
- Auth via `Authorization` header; constant string compared, defaults to `coolio`.

## What is deferred to later phases

- ffmpeg filter chain (radio click splicing, silicon convolution, mask voice
  filters). The gateway currently ignores `filter` and `special_filters` query
  parameters.
- Pitch shift via rubberband. `/pitch-available` returns 500 so SStts keeps
  `pitch_enabled = FALSE` and the URL templating substitutes 0 in.
- Real blips synthesis. `/tts-blips` currently returns the same audio as `/tts`.
- Result caching (sha256 LRU of recent utterances).

## Build

```
docker build -t reduxstation-tts:phase1 docker/tts
```

The build downloads both voice models from Hugging Face at image build time
(~125 MB). First build takes a couple of minutes; subsequent rebuilds reuse the
voice-data layer.

## Run

```
docker run --rm \
    -p 127.0.0.1:5500:5500 \
    -e TTS_AUTHORIZATION_TOKEN=$(openssl rand -hex 32) \
    --name tts \
    reduxstation-tts:phase1
```

Set `TTS_AUTHORIZATION_TOKEN` to a strong random string in production; the
default value `coolio` is fine for local smoke testing. The game container
must send the same value in `TTS_HTTP_TOKEN` in `hippiestation_config.txt`.

## Smoke test

```
TOKEN=coolio
curl -fsS -H "Authorization: $TOKEN" http://localhost:5500/tts-voices | head -5
curl -fsS -H "Authorization: $TOKEN" http://localhost:5500/health-check
curl -fsS -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    --data '{"text":"hello there general kenobi"}' \
    "http://localhost:5500/tts?voice=VCTK%20Man%2002&identifier=test&filter=&pitch=0&special_filters=" \
    -o /tmp/test.ogg
ffprobe /tmp/test.ogg
```

The first request after start triggers ONNX warmup; expect 1 to 4 seconds for
the cold path. Subsequent requests on the same voice land in tens to low
hundreds of milliseconds depending on host CPU.

## Wire to the game container

In `ReduxStation/config/docker-compose.yml`, add a service alongside the existing
`reduxstation-tgs` entry:

```yaml
  tts:
    image: reduxstation-tts:phase1
    restart: unless-stopped
    expose:
      - "5500"
    environment:
      - TTS_AUTHORIZATION_TOKEN=${TTS_TOKEN}
    cpus: "8"
    mem_limit: "4g"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:5500/health-check"]
      interval: 5s
      timeout: 2s
      retries: 3
```

Then in `ReduxStation/config/hippiestation_config.txt`:

```
TTS_HTTP_URL http://tts:5500
TTS_HTTP_TOKEN <same value as TTS_TOKEN env>
TTS_MAX_CONCURRENT_REQUESTS 4
TTS_HTTP_TIMEOUT_SECONDS 30
```

When `TTS_HTTP_URL` is unset, SStts returns `SS_INIT_NO_NEED` at boot and the
subsystem disables itself silently. Safe to leave the config keys absent
while we iterate on the gateway image.

## Capacity expectations

On the live VPS (AMD EPYC 9645 Zen 5, 16 vCPUs):

- Cold-start per worker: 1 to 4 seconds (ONNX model load).
- Per-request synthesis: 25 to 80 ms for typical SS13 utterances (5 to 50 chars).
- Memory: ~250 MB resident per worker, ~500 MB total for the two voice models
  plus Python overhead. Headroom is large; the `mem_limit: 4g` above is loose.
- Throughput: comfortably 30 to 60 requests per second sustained per single
  aiohttp worker. Phase 1 ships one worker; Phase 5 may scale out behind a
  load balancer.

See `.claude/tts_performance_analysis.md` for the full benchmark trail.

## Architecture decisions and where to look next

- The Coqui-VITS path tg ships in `tools/tts/` is materially slower on CPU
  (~5 to 10x) and tg's own production operators refuse to run it on CPU.
  We picked Piper instead. Background: `.claude/tts_performance_analysis.md`.
- The full porting analysis for the DM-side is in `.claude/tts_dependency_audit.md`.
- The Phase 1 to 4 plan is in `.claude/tts_porting_synthesis.md`.
