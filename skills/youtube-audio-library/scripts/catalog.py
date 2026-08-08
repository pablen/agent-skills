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
  list                           dump both csv files as JSON
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


def cmd_init(args):
    root = Path(args.library_root)
    (root / "originals").mkdir(parents=True, exist_ok=True)
    (root / "converted").mkdir(parents=True, exist_ok=True)
    ensure_csv(catalog_csv(root), CATALOG_HEADER)
    ensure_csv(files_csv(root), FILES_HEADER)
    print(json.dumps({"status": "ok", "library_root": str(root.resolve())}))


def cmd_add_song(args):
    root = Path(args.library_root)
    path = catalog_csv(root)
    ensure_csv(path, CATALOG_HEADER)
    with path.open("a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerow([
            args.video_id, args.song, args.artist, args.duration_sec,
            args.source_url, date.today().isoformat(), args.notes or "",
        ])
    print(json.dumps({"status": "ok", "added": "catalog.csv", "video_id": args.video_id}))


def cmd_add_file(args):
    root = Path(args.library_root)
    fmt, bitrate, size_bytes, path_val = args.format, args.bitrate, args.size_bytes, args.path

    if args.from_json:
        raw = sys.stdin.read() if args.from_json == "-" else Path(args.from_json).read_text(encoding="utf-8")
        data = json.loads(raw)
        fmt = fmt or data.get("format")
        bitrate = bitrate or data.get("bitrate_kbps")
        size_bytes = size_bytes or data.get("size_bytes")
        path_val = path_val or data.get("path")

    missing = [name for name, val in (
        ("format", fmt), ("bitrate", bitrate), ("size_bytes", size_bytes), ("path", path_val),
    ) if val is None]
    if missing:
        print(json.dumps({
            "status": "failed",
            "error": f"missing fields: {', '.join(missing)} (pass explicitly or via --from-json)",
        }))
        return

    path = files_csv(root)
    ensure_csv(path, FILES_HEADER)
    with path.open("a", newline="", encoding="utf-8") as f:
        csv.writer(f).writerow([
            args.video_id, args.kind, fmt, bitrate, size_bytes, path_val, date.today().isoformat(),
        ])
    print(json.dumps({"status": "ok", "added": "files.csv", "video_id": args.video_id}))


def cmd_list(args):
    root = Path(args.library_root)

    def read(path: Path):
        if not path.exists():
            return []
        with path.open(newline="", encoding="utf-8") as f:
            return list(csv.DictReader(f))

    print(json.dumps({
        "catalog": read(catalog_csv(root)),
        "files": read(files_csv(root)),
    }, ensure_ascii=False, indent=2))


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

    sub.add_parser("list").set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
