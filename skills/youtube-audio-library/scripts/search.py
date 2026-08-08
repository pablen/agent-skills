#!/usr/bin/env python3
"""Search YouTube for candidate videos (metadata only, no download).

Usage:
  search.py --query "maria elena walsh canciones" [--count 20]
            [--min-duration 60] [--max-duration 180]

Prints a JSON array of results. Filtering (which results are "the right
version") is NOT done here — that judgment call belongs to the agent, looking
at title/channel/view_count. This script only fetches cheap metadata and
applies the numeric duration filter, if given.
"""
import argparse
import json
import subprocess
import sys

from common import emit


def search(query: str, count: int, min_duration, max_duration):
    cmd = [
        "yt-dlp", f"ytsearch{count}:{query}",
        "--flat-playlist", "-j", "--no-warnings",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return {"error": result.stderr.strip() or "yt-dlp search failed"}

    results = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        duration = entry.get("duration")

        if min_duration is not None and (duration is None or duration < min_duration):
            continue
        if max_duration is not None and (duration is None or duration > max_duration):
            continue

        results.append({
            "video_id": entry.get("id"),
            "title": entry.get("title"),
            "channel": entry.get("channel") or entry.get("uploader"),
            "duration_sec": duration,
            "view_count": entry.get("view_count"),
            "url": entry.get("url") or f"https://www.youtube.com/watch?v={entry.get('id')}",
        })
    return {"query": query, "count_requested": count, "results": results}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", required=True)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--min-duration", type=int, default=None, help="seconds")
    parser.add_argument("--max-duration", type=int, default=None, help="seconds")
    args = parser.parse_args()

    emit(search(args.query, args.count, args.min_duration, args.max_duration))


if __name__ == "__main__":
    main()
