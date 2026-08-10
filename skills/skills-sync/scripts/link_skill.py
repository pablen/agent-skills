#!/usr/bin/env python3
"""Safely turn one path into a symlink pointing at another.

Mirrors organize.py's caution in the youtube-audio-library skill: never
clobber real content by default. If --target is already real content
(a file or a directory that isn't a symlink), this refuses and reports
"exists_real" instead of touching it — the agent must have already shown
the user a diff (diff_skill.py) and gotten explicit confirmation before
passing --replace.

Usage:
  link_skill.py --target <path> --points-to <path> [--replace] [--relink]
"""
import argparse
import os
import shutil
from pathlib import Path

from common import emit


def link(target: Path, points_to: Path, replace: bool, relink: bool):
    if target.is_symlink():
        current = target.resolve()
        if current == points_to.resolve():
            return {"status": "already_ok", "target": str(target)}
        if not relink:
            return {
                "status": "symlink_mismatch",
                "target": str(target),
                "points_to": str(current),
                "hint": "pass --relink to repoint it",
            }
        target.unlink()
    elif target.exists():
        if not replace:
            return {
                "status": "exists_real",
                "target": str(target),
                "hint": "diff it first (diff_skill.py), then pass --replace once confirmed",
            }
        if target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()

    target.parent.mkdir(parents=True, exist_ok=True)
    relative = os.path.relpath(points_to.resolve(), start=target.parent)
    target.symlink_to(relative)
    return {"status": "ok", "target": str(target), "points_to_relative": relative}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, help="Path that should become a symlink")
    parser.add_argument("--points-to", required=True, help="Where the symlink should point")
    parser.add_argument("--replace", action="store_true", help="Allow replacing real (non-symlink) content")
    parser.add_argument("--relink", action="store_true", help="Allow repointing a symlink that points elsewhere")
    args = parser.parse_args()

    emit(link(
        Path(args.target).expanduser(),
        Path(args.points_to).expanduser(),
        args.replace,
        args.relink,
    ))


if __name__ == "__main__":
    main()
