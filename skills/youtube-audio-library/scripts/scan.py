#!/usr/bin/env python3
"""Inventory audio files already on disk under a directory (recursive).

Useful to import a pre-existing library that doesn't follow this skill's
naming convention yet. Only probes files and reports metadata — it never
renames or moves anything. Deciding what to do with the results (rename in
bulk, add to catalog, etc.) is the agent's job and requires explicit user
confirmation per references/rationale.md decision #10.

Usage: scan.py --dir <path> [--ext mp3 --ext ogg ...]
"""
import argparse
from pathlib import Path

from common import emit, ffprobe_info

DEFAULT_EXTS = {"mp3", "m4a", "opus", "ogg", "webm", "flac", "wav", "aac"}


def scan(directory: Path, exts):
    files = []
    for path in sorted(directory.rglob("*")):
        if not path.is_file() or path.suffix.lower().lstrip(".") not in exts:
            continue
        try:
            info = ffprobe_info(path)
        except Exception as e:
            files.append({"path": str(path), "error": str(e)})
            continue
        files.append({"path": str(path), **info})
    return {"dir": str(directory.resolve()), "count": len(files), "files": files}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--ext", action="append", default=None)
    args = parser.parse_args()

    exts = set(e.lower() for e in args.ext) if args.ext else DEFAULT_EXTS
    emit(scan(Path(args.dir), exts))


if __name__ == "__main__":
    main()
