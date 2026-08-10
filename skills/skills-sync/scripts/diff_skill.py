#!/usr/bin/env python3
"""Show what differs between two copies of a skill folder.

Meant to run right before link_skill.py --replace on a real_dir_diverges
entry, so the agent has something concrete to show the user rather than
"they differ, trust me". --full also prints unified diffs for small text
files (skips anything binary-looking or large).

Usage: diff_skill.py --a <path> --b <path> [--full]
"""
import argparse
import subprocess
from pathlib import Path

from common import emit, run

MAX_FULL_DIFF_BYTES = 20_000


def list_differences(a: Path, b: Path):
    returncode, stdout, _ = run(["diff", "-rq", str(a), str(b)], timeout=20)
    if returncode == 0:
        return {"identical": True, "lines": []}
    return {"identical": False, "lines": [l for l in stdout.splitlines() if l.strip()]}


def full_diff(a: Path, b: Path):
    if not a.is_file() or not b.is_file():
        return None
    try:
        if a.stat().st_size > MAX_FULL_DIFF_BYTES or b.stat().st_size > MAX_FULL_DIFF_BYTES:
            return "(skipped: file too large)"
    except OSError:
        return None
    result = subprocess.run(["diff", "-u", str(a), str(b)], capture_output=True, text=True)
    return result.stdout or "(no textual diff — possibly binary)"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--a", required=True)
    parser.add_argument("--b", required=True)
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()

    a, b = Path(args.a).expanduser(), Path(args.b).expanduser()
    result = {"a": str(a), "b": str(b), **list_differences(a, b)}

    if args.full and not result["identical"]:
        details = []
        for line in result["lines"]:
            if line.startswith("Files ") and " differ" in line:
                parts = line[len("Files "):].rsplit(" differ", 1)[0].split(" and ")
                if len(parts) == 2:
                    details.append({"file": parts[0], "diff": full_diff(Path(parts[0]), Path(parts[1]))})
        result["full_diffs"] = details

    emit(result)


if __name__ == "__main__":
    main()
