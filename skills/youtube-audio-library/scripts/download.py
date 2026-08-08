#!/usr/bin/env python3
"""Download best-available audio for one video into a staging area.

Does NOT decide the final filename/folder — that requires the song/artist
names the agent has already normalized (see organize.py). One automatic
retry on failure, per references/rationale.md decision #9.

Usage: download.py --url <youtube_url_or_id> --library-root <path>
"""
import argparse
import subprocess
import sys
from pathlib import Path

from common import emit, ffprobe_info


def run_download(url: str, staging: Path) -> subprocess.CompletedProcess:
    cmd = [
        "yt-dlp", "-f", "bestaudio", "-x", "--no-playlist",
        "-o", str(staging / "%(id)s.%(ext)s"),
        "--print", "after_move:filepath",
        "--no-warnings",
        url,
    ]
    return subprocess.run(cmd, capture_output=True, text=True)


def download(url: str, library_root: Path):
    staging = library_root / ".staging"
    staging.mkdir(parents=True, exist_ok=True)

    result = run_download(url, staging)
    attempts = 1
    if result.returncode != 0:
        result = run_download(url, staging)  # 1 retry
        attempts = 2

    if result.returncode != 0:
        return {"status": "failed", "attempts": attempts, "error": result.stderr.strip()[-2000:]}

    filepath = result.stdout.strip().splitlines()[-1]
    path = Path(filepath)
    if not path.exists():
        return {"status": "failed", "attempts": attempts, "error": "download reported success but file not found"}

    info = ffprobe_info(path)
    return {
        "status": "ok",
        "attempts": attempts,
        "staged_path": str(path),
        "format": path.suffix.lstrip("."),
        **info,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--library-root", default=".")
    args = parser.parse_args()

    emit(download(args.url, Path(args.library_root)))


if __name__ == "__main__":
    main()
