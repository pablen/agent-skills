#!/usr/bin/env python3
"""Deterministic reads/writes for catalog.csv and files.csv.

This script does NOT decide anything (no dedup/fuzzy-match logic) — it only
performs punctual, well-defined operations. Cross-referencing search results
against the catalog to decide what's missing is the agent's job (see
references/rationale.md, decision #5).

Subcommands:
  init                          create originals/, converted/, catalog.csv,
                                 files.csv in --library-root if missing
  add-song --video-id ... --song ... --artist ... --duration-sec ...
           --source-url ... [--notes ...]
  add-file --video-id ... --kind original|converted [--format ... --bitrate ...
           --size-bytes ... --path ...] [--from-json <path|->]
           (format/bitrate/size_bytes/path can come from organize.py's or
           convert.py's own JSON output instead of being re-typed)
  list [--artist ... | --video-id ...]
                                 dump both csv files as JSON, optionally
                                 filtered (keeps the library readable as it grows)
"""
import argparse
import csv
import json
import sys
from datetime import date
from pathlib import Path

CATALOG_HEADER = ["video_id", "song", "artist", "duration_sec", "source_url", "download_date", "notes"]
FILES_HEADER = ["video_id", "kind", "format", "bitrate", "size_bytes", "path", "created_date"]


def catalog_csv(root: Path) -> Path:
    return root / "catalog.csv"


def files_csv(root: Path) -> Path:
    return root / "files.csv"


def ensure_csv(path: Path, header):
    if not path.exists():
        with path.open("w", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(header)


def find_rows(path: Path, video_id: str, kind=None):
    """Rows already on disk matching video_id (and kind, for files.csv)."""
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return [
        r for r in rows
        if r["video_id"] == video_id and (kind is None or r.get("kind") == kind)
    ]


def cmd_init(args):
    root = Path(args.library_root)
    (root / "originals").mkdir(parents=True, exist_ok=True)
    (root / "converted").mkdir(parents=True, exist_ok=True)
    ensure_csv(catalog_csv(root), CATALOG_HEADER)
    ensure_csv(files_csv(root), FILES_HEADER)
    print(json.dumps({"status": "ok", "library_root": str(root.resolve())}))


def add_song(root: Path, video_id, song, artist, duration_sec, source_url, notes=""):
    """Append one row to catalog.csv. Returns the same dict cmd_add_song prints."""
    path = catalog_csv(root)
    ensure_csv(path, CATALOG_HEADER)
    existing = find_rows(path, video_id)
    with path.open("a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerow([
            video_id, song, artist, duration_sec, source_url, date.today().isoformat(), notes or "",
        ])
    result = {"status": "ok", "added": "catalog.csv", "video_id": video_id}
    if existing:
        result["warning"] = (
            f"video_id {video_id} was already in catalog.csv as "
            f"\"{existing[0]['song']}\" — check for a duplicate row"
        )
    return result


def add_file(root: Path, video_id, kind, fmt, bitrate, size_bytes, path_val):
    """Append one row to files.csv. Returns the same dict cmd_add_file prints."""
    missing = [name for name, val in (
        ("format", fmt), ("bitrate", bitrate), ("size_bytes", size_bytes), ("path", path_val),
    ) if val is None]
    if missing:
        return {"status": "failed", "error": f"missing fields: {', '.join(missing)}"}

    path = files_csv(root)
    ensure_csv(path, FILES_HEADER)
    existing = find_rows(path, video_id, kind=kind)
    with path.open("a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerow([video_id, kind, fmt, bitrate, size_bytes, path_val, date.today().isoformat()])
    result = {"status": "ok", "added": "files.csv", "video_id": video_id}
    if existing:
        result["warning"] = (
            f"video_id {video_id} already has a '{kind}' row in files.csv "
            f"({existing[0]['path']}) — check for a duplicate"
        )
    return result


def cmd_add_song(args):
    print(json.dumps(
        add_song(Path(args.library_root), args.video_id, args.song, args.artist,
                  args.duration_sec, args.source_url, args.notes),
        ensure_ascii=False,
    ))


def cmd_add_file(args):
    fmt, bitrate, size_bytes, path_val = args.format, args.bitrate, args.size_bytes, args.path

    if args.from_json:
        raw = sys.stdin.read() if args.from_json == "-" else Path(args.from_json).read_text(encoding="utf-8")
        data = json.loads(raw)
        fmt = fmt or data.get("format")
        bitrate = bitrate or data.get("bitrate_kbps")
        size_bytes = size_bytes or data.get("size_bytes")
        path_val = path_val or data.get("path")

    result = add_file(Path(args.library_root), args.video_id, args.kind, fmt, bitrate, size_bytes, path_val)
    if result["status"] == "failed":
        result["error"] += " (pass explicitly or via --from-json)"
    print(json.dumps(result, ensure_ascii=False))


def cmd_list(args):
    root = Path(args.library_root)

    def read(path: Path):
        if not path.exists():
            return []
        with path.open(newline="", encoding="utf-8") as f:
            return list(csv.DictReader(f))

    catalog_rows = read(catalog_csv(root))
    files_rows = read(files_csv(root))

    if args.video_id:
        catalog_rows = [r for r in catalog_rows if r["video_id"] == args.video_id]
    if args.artist:
        needle = args.artist.lower()
        catalog_rows = [r for r in catalog_rows if r["artist"].lower() == needle]

    if args.video_id or args.artist:
        kept_ids = {r["video_id"] for r in catalog_rows}
        files_rows = [r for r in files_rows if r["video_id"] in kept_ids]

    print(json.dumps({"catalog": catalog_rows, "files": files_rows}, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--library-root", default=".")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("init").set_defaults(func=cmd_init)

    p = sub.add_parser("add-song")
    p.add_argument("--video-id", required=True)
    p.add_argument("--song", required=True)
    p.add_argument("--artist", required=True)
    p.add_argument("--duration-sec", required=True)
    p.add_argument("--source-url", required=True)
    p.add_argument("--notes", default="")
    p.set_defaults(func=cmd_add_song)

    p = sub.add_parser("add-file")
    p.add_argument("--video-id", required=True)
    p.add_argument("--kind", required=True, choices=["original", "converted"])
    p.add_argument("--format")
    p.add_argument("--bitrate")
    p.add_argument("--size-bytes")
    p.add_argument("--path")
    p.add_argument("--from-json", help=(
        "Path to a JSON file, or '-' for stdin, containing organize.py/convert.py's "
        "own output. Fills format/bitrate/size_bytes/path from it when not passed "
        "explicitly, so those numbers don't need to be re-typed by hand."
    ))
    p.set_defaults(func=cmd_add_file)

    p = sub.add_parser("list")
    p.add_argument("--artist", help="Exact match, case-insensitive")
    p.add_argument("--video-id")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
