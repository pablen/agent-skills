#!/usr/bin/env python3
"""Move a staged/downloaded file into the originals/<Artist>/ convention.

Refuses to overwrite an existing file at the destination (reports it instead)
rather than silently clobbering something.

Usage: organize.py --src <path> --library-root <path> --artist "..." --song "..."
"""
import argparse
import shutil
from pathlib import Path

from common import emit, ffprobe_info, originals_path


def organize(src: Path, library_root: Path, artist: str, song: str):
    ext = src.suffix.lstrip(".")
    dest = originals_path(library_root, artist, song, ext)

    if dest.exists():
        return {"status": "exists", "path": str(dest)}

    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dest))
    info = ffprobe_info(dest)
    return {"status": "ok", "path": str(dest), "format": ext, **info}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True)
    parser.add_argument("--library-root", default=".")
    parser.add_argument("--artist", required=True)
    parser.add_argument("--song", required=True)
    args = parser.parse_args()

    emit(organize(Path(args.src), Path(args.library_root), args.artist, args.song))


if __name__ == "__main__":
    main()
