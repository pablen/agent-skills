#!/usr/bin/env python3
"""Conditionally convert an original audio file and tag it (ID3).

Skip rule (references/rationale.md decision #7): convert unless the source is
already <target-format> at a bitrate <= <target-bitrate>. A source in any
other container/codec is always converted, regardless of its bitrate, because
the goal is a specific compatible target container, not just "don't downgrade".

On failure, reports the error and does not raise — batches are driven by the
agent calling this once per file, so one failure should not stop the rest.

Usage:
  convert.py --src <original_path> --library-root <path> --artist "..."
             --song "..." [--target-format mp3] [--target-bitrate 192]
"""
import argparse
import subprocess
from pathlib import Path

from common import converted_path, emit, ffprobe_info


def maybe_tag(dest: Path, artist: str, song: str, fmt: str):
    if fmt != "mp3":
        return
    from mutagen.easyid3 import EasyID3
    from mutagen.mp3 import MP3

    try:
        tags = EasyID3(dest)
    except Exception:
        MP3(dest).add_tags()
        tags = EasyID3(dest)
    tags["title"] = song
    tags["artist"] = artist
    tags.save()


def convert(src: Path, library_root: Path, artist: str, song: str, target_format: str, target_bitrate: int):
    src_info = ffprobe_info(src)
    src_format = src.suffix.lstrip(".")

    if src_format == target_format and src_info["bitrate_kbps"] and src_info["bitrate_kbps"] <= target_bitrate:
        return {"status": "skipped", "reason": "source already meets target format/bitrate", "source": src_info}

    format_quality = f"{target_format}-{target_bitrate}"
    dest = converted_path(library_root, format_quality, artist, song, target_format)

    if dest.exists():
        return {"status": "exists", "path": str(dest)}

    dest.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-y", "-i", str(src),
        "-b:a", f"{target_bitrate}k", "-vn",
        str(dest),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return {"status": "failed", "error": result.stderr.strip()[-2000:]}

    try:
        maybe_tag(dest, artist, song, target_format)
    except Exception as e:
        return {"status": "ok", "path": str(dest), "tag_warning": str(e), **ffprobe_info(dest)}

    return {"status": "ok", "path": str(dest), "format": target_format, **ffprobe_info(dest)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True)
    parser.add_argument("--library-root", default=".")
    parser.add_argument("--artist", required=True)
    parser.add_argument("--song", required=True)
    parser.add_argument("--target-format", default="mp3")
    parser.add_argument("--target-bitrate", type=int, default=192)
    args = parser.parse_args()

    emit(convert(
        Path(args.src), Path(args.library_root), args.artist, args.song,
        args.target_format, args.target_bitrate,
    ))


if __name__ == "__main__":
    main()
