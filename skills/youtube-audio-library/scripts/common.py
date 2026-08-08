"""Shared helpers for the youtube-audio-library skill scripts."""
import json
import re
import subprocess
from pathlib import Path

INVALID_CHARS = re.compile(r'[\\/:*?"<>|]')


def sanitize(name: str) -> str:
    """Replace filesystem-unsafe characters with '-' and collapse whitespace."""
    cleaned = INVALID_CHARS.sub("-", name)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned


def song_filename(song: str, artist: str, ext: str) -> str:
    return f"{sanitize(song)} - {sanitize(artist)}.{ext}"


def originals_path(library_root: Path, artist: str, song: str, ext: str) -> Path:
    return library_root / "originals" / sanitize(artist) / song_filename(song, artist, ext)


def converted_path(library_root: Path, format_quality: str, artist: str, song: str, ext: str) -> Path:
    return library_root / "converted" / sanitize(format_quality) / sanitize(artist) / song_filename(song, artist, ext)


def ffprobe_info(path: Path) -> dict:
    """Return {format, codec, bitrate_kbps, duration_sec, size_bytes} for an audio file."""
    cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", "-show_streams", str(path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    fmt = data.get("format", {})
    audio_stream = next((s for s in data.get("streams", []) if s.get("codec_type") == "audio"), {})

    bitrate = audio_stream.get("bit_rate") or fmt.get("bit_rate")
    bitrate_kbps = round(int(bitrate) / 1000) if bitrate else None

    return {
        "codec": audio_stream.get("codec_name"),
        "bitrate_kbps": bitrate_kbps,
        "duration_sec": round(float(fmt.get("duration", 0))) if fmt.get("duration") else None,
        "size_bytes": int(fmt.get("size")) if fmt.get("size") else path.stat().st_size,
    }


def emit(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False, indent=2))
