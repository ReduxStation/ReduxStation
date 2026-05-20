"""Piper-backed TTS gateway for ReduxStation.

Implements the HTTP contract SStts (code/controllers/subsystem/tts.dm) expects.
Phase 1 scope: pure Piper inference, ogg output via ffmpeg, no filter chain,
no pitch, no blips synthesis (blips endpoint returns the same audio as /tts
for now). Auth via Authorization header.

Voice catalog is built by introspecting the speaker_id_map embedded in each
voice's .onnx.json config. Two models ship together:

    en_GB-vctk-medium       109 UK English VCTK speakers ("VCTK Man 01" etc.)
    en_US-libritts_r-medium 904 American LibriTTS-R speakers ("LibriTTS 0001" etc.)

Phases 3+ layer the ffmpeg filter chain (radio click splicing, silicon
convolution) and rubberband pitch shift on top of this skeleton.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

from aiohttp import web

# Piper Python wrapper. The PiperVoice class wraps the ONNX session and the
# tokenizer; .synthesize() yields PCM 16-bit at the model's native sample rate.
from piper import PiperVoice


LOG = logging.getLogger("tts-gateway")
logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

VOICES_DIR = Path(os.environ.get("TTS_VOICES_DIR", "/app/voices"))
AUTH_TOKEN = os.environ.get("TTS_AUTHORIZATION_TOKEN", "coolio")
BIND_HOST = os.environ.get("TTS_BIND_HOST", "0.0.0.0")
BIND_PORT = int(os.environ.get("TTS_BIND_PORT", "5500"))

# Maximum body size we accept in /tts. 300 chars is the SS-side scrub cap, give
# headroom for JSON envelope. Anything bigger is almost certainly a misuse.
MAX_BODY_BYTES = 4096


# ---------------------------------------------------------------------------
# Voice catalog construction
# ---------------------------------------------------------------------------

@dataclass
class VoiceEntry:
    """One row in the voice catalog: a human-friendly name that maps to a
    (PiperVoice instance, speaker_id) tuple. speaker_id is None for single-
    speaker models."""

    label: str
    voice: PiperVoice
    speaker_id: int | None


def _read_config(onnx_path: Path) -> dict:
    config_path = onnx_path.with_suffix(onnx_path.suffix + ".json")
    if not config_path.exists():
        # Some voice packages ship the JSON without the double suffix.
        config_path = onnx_path.with_suffix(".onnx.json")
    with config_path.open() as fh:
        return json.load(fh)


def _load_voice(onnx_path: Path) -> PiperVoice:
    LOG.info("Loading Piper voice: %s", onnx_path.name)
    return PiperVoice.load(str(onnx_path))


def _label_for_vctk(speaker_id: int, gender_map: Dict[int, str]) -> str:
    gender_word = gender_map.get(speaker_id, "Speaker")
    return f"VCTK {gender_word} {speaker_id:02d}"


# VCTK gender map. The VCTK corpus speakers p225 through p299 have known genders
# from the corpus README. The model's speaker_id_map maps "p225" -> 0,
# "p226" -> 1, etc. SStts.random_tts_voice() relies on "Man"/"Woman" substring
# matching for gender-filtered lookups, so we use those exact words in labels.
VCTK_GENDERS_BY_SPEAKER_NAME: Dict[str, str] = {
    # Source: VCTK speaker-info.txt. F = Woman, M = Man.
    # First 30 entries; remaining IDs default to "Speaker" (no gender) since
    # the corpus README labels are not fully captured here and we do not want
    # to assert a wrong gender. random_tts_voice falls back gracefully.
    "p225": "Woman", "p226": "Man", "p227": "Man", "p228": "Woman",
    "p229": "Woman", "p230": "Woman", "p231": "Woman", "p232": "Man",
    "p233": "Woman", "p234": "Woman", "p236": "Woman", "p237": "Man",
    "p238": "Woman", "p239": "Woman", "p240": "Woman", "p241": "Man",
    "p243": "Man", "p244": "Woman", "p245": "Man", "p246": "Man",
    "p247": "Man", "p248": "Woman", "p249": "Woman", "p250": "Woman",
    "p251": "Man", "p252": "Man", "p253": "Woman", "p254": "Man",
    "p255": "Man", "p256": "Man", "p257": "Man", "p258": "Man",
    "p259": "Man", "p260": "Man", "p261": "Woman", "p262": "Woman",
    "p263": "Man", "p264": "Woman", "p265": "Woman", "p266": "Woman",
    "p267": "Woman", "p268": "Woman", "p269": "Woman", "p270": "Man",
    "p271": "Man", "p272": "Man", "p273": "Man", "p274": "Man",
    "p275": "Man", "p276": "Woman", "p277": "Woman", "p278": "Man",
    "p279": "Man", "p280": "Woman", "p281": "Man", "p282": "Woman",
    "p283": "Man", "p284": "Man", "p285": "Man", "p286": "Man",
    "p287": "Man", "p288": "Woman", "p292": "Man", "p293": "Woman",
    "p294": "Woman", "p295": "Woman", "p297": "Woman", "p298": "Man",
    "p299": "Woman", "p300": "Woman", "p301": "Woman", "p302": "Man",
    "p303": "Woman", "p304": "Man", "p305": "Woman", "p306": "Woman",
    "p307": "Woman", "p308": "Woman", "p310": "Woman", "p311": "Man",
    "p312": "Woman", "p313": "Woman", "p314": "Woman", "p316": "Man",
    "p317": "Woman", "p318": "Woman", "p323": "Woman", "p326": "Man",
    "p329": "Woman", "p330": "Woman", "p333": "Woman", "p334": "Man",
    "p335": "Woman", "p336": "Woman", "p339": "Woman", "p340": "Woman",
    "p341": "Woman", "p343": "Woman", "p345": "Man", "p347": "Man",
    "p351": "Woman", "p360": "Man", "p361": "Woman", "p362": "Woman",
    "p363": "Man", "p364": "Man", "p374": "Man", "p376": "Man",
}


def build_catalog() -> Dict[str, VoiceEntry]:
    """Discover voice models in VOICES_DIR and build the voice catalog."""

    catalog: Dict[str, VoiceEntry] = {}

    vctk_onnx = VOICES_DIR / "en_GB-vctk-medium.onnx"
    if vctk_onnx.exists():
        voice = _load_voice(vctk_onnx)
        config = _read_config(vctk_onnx)
        speaker_id_map = config.get("speaker_id_map") or {}
        # speaker_id_map is {"p225": 0, "p226": 1, ...}
        gender_map_by_id: Dict[int, str] = {}
        for name, sid in speaker_id_map.items():
            gender_map_by_id[int(sid)] = VCTK_GENDERS_BY_SPEAKER_NAME.get(name, "Speaker")
        for name, sid in sorted(speaker_id_map.items(), key=lambda kv: kv[1]):
            label = _label_for_vctk(int(sid) + 1, gender_map_by_id)
            catalog[label] = VoiceEntry(label=label, voice=voice, speaker_id=int(sid))

    libritts_onnx = VOICES_DIR / "en_US-libritts_r-medium.onnx"
    if libritts_onnx.exists():
        voice = _load_voice(libritts_onnx)
        config = _read_config(libritts_onnx)
        speaker_id_map = config.get("speaker_id_map") or {}
        for name, sid in sorted(speaker_id_map.items(), key=lambda kv: kv[1]):
            label = f"LibriTTS {int(sid) + 1:04d}"
            catalog[label] = VoiceEntry(label=label, voice=voice, speaker_id=int(sid))

    LOG.info("Voice catalog built: %d voices total", len(catalog))
    return catalog


# ---------------------------------------------------------------------------
# Synthesis pipeline
# ---------------------------------------------------------------------------

def synthesize_pcm(entry: VoiceEntry, text: str) -> Tuple[bytes, int]:
    """Run Piper inference. Returns (PCM int16 LE bytes, sample_rate)."""

    pcm = bytearray()
    sample_rate = 22050
    for chunk in entry.voice.synthesize(text, speaker_id=entry.speaker_id):
        # piper-tts >= 1.0 yields AudioChunk objects with .audio_int16_bytes and .sample_rate.
        if hasattr(chunk, "audio_int16_bytes"):
            pcm.extend(chunk.audio_int16_bytes)
            sample_rate = getattr(chunk, "sample_rate", sample_rate)
        else:
            # Older piper returns raw int16 numpy arrays.
            pcm.extend(chunk.tobytes())
    return bytes(pcm), sample_rate


def pcm_to_ogg(pcm: bytes, sample_rate: int) -> Tuple[bytes, float]:
    """Encode raw int16 PCM to ogg/vorbis via ffmpeg subprocess.

    Returns (ogg_bytes, duration_seconds).
    """

    if not pcm:
        return b"", 0.0

    duration_seconds = len(pcm) / 2.0 / sample_rate

    # Write to a temp file because ffmpeg's stdin handling for raw PCM is fiddly
    # and we want a stable on-disk representation for the duration probe.
    with tempfile.TemporaryDirectory() as workdir:
        ogg_path = Path(workdir) / "out.ogg"
        cmd = [
            "ffmpeg",
            "-loglevel", "error",
            "-f", "s16le",
            "-ar", str(sample_rate),
            "-ac", "1",
            "-i", "pipe:0",
            "-c:a", "libvorbis",
            "-q:a", "3",
            str(ogg_path),
        ]
        result = subprocess.run(cmd, input=pcm, capture_output=True, check=False)
        if result.returncode != 0:
            LOG.error("ffmpeg encode failed (rc=%s): %s", result.returncode, result.stderr.decode("utf-8", "ignore"))
            raise RuntimeError("ffmpeg encode failed")
        return ogg_path.read_bytes(), duration_seconds


def format_audio_length_header(duration_seconds: float) -> str:
    """Match tg's HH:MM:SS.fff format. SStts parses this with a regex."""

    total = max(duration_seconds, 0.0)
    hours = int(total // 3600)
    minutes = int((total % 3600) // 60)
    seconds = total % 60
    return f"{hours:02d}:{minutes:02d}:{seconds:06.3f}"


# ---------------------------------------------------------------------------
# HTTP handlers
# ---------------------------------------------------------------------------

def _check_auth(request: web.Request) -> bool:
    header = request.headers.get("Authorization", "")
    # SStts sends just the token, no "Bearer " prefix (matches tg's contract).
    return header == AUTH_TOKEN


def _scrub_text(text: str) -> str:
    # SS already scrubs but defense in depth. Keep alphanumerics + basic punct.
    return re.sub(r"[^a-zA-Z0-9 ,?.!'&-]", " ", text)[:300]


async def health_check(request: web.Request) -> web.Response:
    return web.Response(status=200, text="ok")


async def tts_voices(request: web.Request) -> web.Response:
    if not _check_auth(request):
        return web.Response(status=401, text="unauthorized")
    catalog = request.app["catalog"]
    return web.json_response(sorted(catalog.keys()))


async def pitch_available(request: web.Request) -> web.Response:
    if not _check_auth(request):
        return web.Response(status=401, text="unauthorized")
    # Phase 1 does not implement pitch (rubberband ffmpeg filter lands in Phase 3+).
    # Return 500 so SStts.pitch_enabled stays FALSE and pitch defaults to 0 in
    # the URL templating. tg's pattern.
    return web.Response(status=500, text="pitch not implemented in Phase 1")


async def _synthesize_request(request: web.Request) -> web.Response:
    if not _check_auth(request):
        return web.Response(status=401, text="unauthorized")

    voice_name = request.query.get("voice", "")
    catalog = request.app["catalog"]
    if voice_name not in catalog:
        return web.Response(status=404, text=f"unknown voice: {voice_name}")

    raw_body = await request.read()
    if len(raw_body) > MAX_BODY_BYTES:
        return web.Response(status=413, text="body too large")

    try:
        payload = json.loads(raw_body.decode("utf-8")) if raw_body else {}
    except json.JSONDecodeError:
        return web.Response(status=400, text="malformed json body")

    text = _scrub_text(payload.get("text", ""))
    if not text.strip():
        return web.Response(status=400, text="empty text after scrub")

    entry = catalog[voice_name]

    # All synthesis work runs in a thread to keep the aiohttp event loop free.
    loop = asyncio.get_running_loop()
    pcm, sample_rate = await loop.run_in_executor(None, synthesize_pcm, entry, text)
    ogg_bytes, duration = await loop.run_in_executor(None, pcm_to_ogg, pcm, sample_rate)

    headers = {
        "audio-length": format_audio_length_header(duration),
        "Content-Type": "audio/ogg",
    }
    return web.Response(status=200, body=ogg_bytes, headers=headers)


async def tts_endpoint(request: web.Request) -> web.Response:
    return await _synthesize_request(request)


async def tts_blips_endpoint(request: web.Request) -> web.Response:
    # Phase 1: blips path returns the same audio as /tts. Phase 2 (or later) implements
    # per-character blip splicing using a small sample cache.
    return await _synthesize_request(request)


# ---------------------------------------------------------------------------
# App wiring
# ---------------------------------------------------------------------------

def make_app() -> web.Application:
    app = web.Application(client_max_size=MAX_BODY_BYTES)
    catalog = build_catalog()
    if not catalog:
        LOG.error("Voice catalog is empty. Bailing out so the healthcheck stays red.")
        sys.exit(1)
    app["catalog"] = catalog

    app.router.add_get("/health-check", health_check)
    app.router.add_get("/tts-voices", tts_voices)
    app.router.add_get("/pitch-available", pitch_available)
    app.router.add_get("/tts", tts_endpoint)
    app.router.add_get("/tts-blips", tts_blips_endpoint)

    return app


def main() -> None:
    web.run_app(make_app(), host=BIND_HOST, port=BIND_PORT, print=lambda _: None)


if __name__ == "__main__":
    main()
