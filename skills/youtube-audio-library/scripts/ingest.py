#!/usr/bin/env python3
"""Organize a downloaded file and catalog it as an original, in one call.

Chains organize.py + catalog.py's add-song + add-file(kind=original). Doing
those three steps as separate invocations means hand-carrying format/bitrate/
duration between them, which is exactly how a wrong bitrate got typed into a
real catalog. This reads the metadata straight off the organized file via
ffprobe, so nothing is re-typed.

Only covers originals — converting and cataloging a conversion is a separate,
optional step (see convert.py + `catalog.py add-file --from-json`).

Usage:
  ingest.py --src <staged_or_downloaded_path> --library-root <path>
            --artist "..." --song "..." --video-id <id> --source-url <url>
            [--notes ...]
"""
import argparse
from pathlib import Path

from common import emit, ffprobe_info
from organize import organize
from catalog import add_song, add_file


def ingest(src: Path, library_root: Path, artist: str, song: str, video_id: str, source_url: str, notes: str):
    org_result = organize(src, library_root, artist, song)
    if org_result["status"] not in ("ok", "exists"):
        return {"status": "failed", "stage": "organize", **org_result}

    dest = Path(org_result["path"])
    info = ffprobe_info(dest)
    fmt = dest.suffix.lstrip(".")

    song_result = add_song(library_root, video_id, song, artist, info["duration_sec"], source_url, notes)
    file_result = add_file(library_root, video_id, "original", fmt, info["bitrate_kbps"], info["size_bytes"], str(dest))

    return {"status": "ok", "organize": org_result, "song": song_result, "file": file_result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True)
    parser.add_argument("--library-root", default=".")
    parser.add_argument("--artist", required=True)
    parser.add_argument("--song", required=True)
    parser.add_argument("--video-id", required=True)
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--notes", default="")
    args = parser.parse_args()

    emit(ingest(
        Path(args.src), Path(args.library_root), args.artist, args.song,
        args.video_id, args.source_url, args.notes,
    ))


if __name__ == "__main__":
    main()
