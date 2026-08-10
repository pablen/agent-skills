#!/usr/bin/env python3
"""Cross-reference repo, hub, and each tool's skill dir into one status report.

Classifies every (skill, location) pair so the agent can build a plan without
guessing at the raw symlink/dir listing itself. Never writes anything —
link_skill.py does that, only after the agent has presented a plan and the
user confirmed it.

Usage: inventory.py --repo-root <path> [--hub-root ~/.agents/skills]
"""
import argparse
import json
from pathlib import Path

from common import emit, run

DEFAULT_HUB_ROOT = Path.home() / ".agents" / "skills"
LOCKFILE = Path.home() / ".agents" / ".skill-lock.json"

TOOL_DIRS = {
    "claude": Path.home() / ".claude" / "skills",
    "codex": Path.home() / ".codex" / "skills",
    "pi": Path.home() / ".pi" / "agent" / "skills",
    # gemini deliberately excluded: mode "hub_alias", no per-skill dir to check
}


def lockfile_names():
    if not LOCKFILE.exists():
        return set()
    try:
        data = json.loads(LOCKFILE.read_text(encoding="utf-8"))
        return set(data.get("skills", {}).keys())
    except json.JSONDecodeError:
        return set()


def classify(entry_path: Path, expected_target: Path):
    """Status of entry_path relative to what it *should* symlink to."""
    if not entry_path.exists() and not entry_path.is_symlink():
        return {"status": "missing"}
    if entry_path.is_symlink():
        target = entry_path.resolve()
        if target == expected_target.resolve():
            return {"status": "symlink_ok"}
        return {"status": "symlink_wrong", "points_to": str(target)}
    # real file or directory
    returncode, _, _ = run(["diff", "-rq", str(entry_path), str(expected_target)])
    return {"status": "real_dir_identical" if returncode == 0 else "real_dir_diverges"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--hub-root", default=str(DEFAULT_HUB_ROOT))
    args = parser.parse_args()

    repo_root = Path(args.repo_root).expanduser()
    hub_root = Path(args.hub_root).expanduser()
    repo_skills_dir = repo_root / "skills"

    protected = lockfile_names()
    repo_skills = sorted(p.name for p in repo_skills_dir.iterdir() if p.is_dir())

    report = {"repo_root": str(repo_root), "hub_root": str(hub_root), "skills": {}}

    # Anything already in the hub but NOT one of our repo skills: flag if it's
    # lockfile-protected (leave alone) or unexplained (surface, don't touch).
    hub_extra = []
    if hub_root.is_dir():
        for entry in hub_root.iterdir():
            if entry.name.startswith(".") or entry.name in repo_skills:
                continue
            hub_extra.append({
                "name": entry.name,
                "protected": entry.name in protected,
            })
    report["hub_extra"] = hub_extra

    for name in repo_skills:
        repo_skill_path = repo_skills_dir / name
        hub_entry = hub_root / name
        skill_report = {
            "hub": {"path": str(hub_entry), **classify(hub_entry, repo_skill_path)},
            "tools": {},
        }
        for tool, tool_dir in TOOL_DIRS.items():
            tool_entry = tool_dir / name
            skill_report["tools"][tool] = {
                "path": str(tool_entry),
                "tool_dir_exists": tool_dir.is_dir(),
                **classify(tool_entry, hub_entry),
            }
        report["skills"][name] = skill_report

    emit(report)


if __name__ == "__main__":
    main()
