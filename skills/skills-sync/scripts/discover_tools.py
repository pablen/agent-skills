#!/usr/bin/env python3
"""Report where each known agent looks for skills, plus a deep-scan fallback.

Known tools live in TOOLS below, each with a resolution `mode`:
  - "per_skill_symlink": the tool has its own skills/ directory where each
    skill is expected to be a separate named entry (a symlink into the hub,
    ideally). Claude Code, Codex, and Pi all work this way today.
  - "hub_alias": the tool reads the hub directory directly as a first-class
    alias — no per-tool directory or per-skill symlinks needed, just confirm
    the tool still resolves the hub's skills, ideally via its own verify_cmd.
    Gemini CLI works this way (see references/rationale.md).

For a *new or unrecognized* tool (not in TOOLS, or whose known candidates
don't exist despite the tool being installed), this is the deep-scan fallback
that actually found Gemini's mechanism by hand in a real session: locate the
tool's installed package via `which` (+ a package-manager-specific lookup),
then grep its shipped docs/source for "skill" mentions. This is inherently
exploratory — it reports raw hits, it does NOT conclude support one way or
the other. That interpretation is the agent's job.

Usage:
  discover_tools.py [--tool claude --tool gemini ...]   # default: all known
  discover_tools.py --deep-scan-unknown <name> --binary <bin>
                                                          # fallback only, for
                                                          # a tool not in TOOLS
"""
import argparse
from pathlib import Path

from common import emit, run

TOOLS = {
    "claude": {
        "mode": "per_skill_symlink",
        "candidates": ["~/.claude/skills"],
        "binary": "claude",
    },
    "codex": {
        "mode": "per_skill_symlink",
        "candidates": ["~/.codex/skills"],
        "binary": "codex",
    },
    "gemini": {
        "mode": "hub_alias",
        "candidates": ["~/.gemini/skills"],
        "binary": "gemini",
        "verify_cmd": ["gemini", "skills", "list", "--all"],
    },
    "pi": {
        "mode": "hub_alias",
        # Pi's own docs (docs/skills.md, shipped with @earendil-works/pi-coding-agent)
        # list ~/.agents/skills/ as a global skill location alongside its own
        # ~/.pi/agent/skills/ — no per-skill symlink needed, same as Gemini.
        "candidates": ["~/.pi/agent/skills"],
        "binary": "pi",
    },
}


def inspect_dir(path: Path):
    if not path.exists():
        return {"path": str(path), "exists": False, "entries": []}
    entries = []
    for entry in sorted(path.iterdir()):
        if entry.name.startswith("."):
            continue
        if entry.is_symlink():
            entries.append({"name": entry.name, "kind": "symlink", "target": str(entry.resolve())})
        elif entry.is_dir():
            entries.append({"name": entry.name, "kind": "dir"})
    return {"path": str(path), "exists": True, "entries": entries}


def locate_package_dirs(binary: str):
    """Best-effort: where might this tool's installed files live?"""
    dirs = []
    returncode, stdout, _ = run(["which", binary])
    binary_path = stdout.strip() if returncode == 0 else None

    returncode, stdout, _ = run(["npm", "root", "-g"])
    if returncode == 0:
        npm_root = Path(stdout.strip())
        for pkg_dir in npm_root.glob(f"*{binary}*"):
            dirs.append(pkg_dir)
        for scope_dir in npm_root.glob("@*"):
            for pkg_dir in scope_dir.glob(f"*{binary}*"):
                dirs.append(pkg_dir)

    return binary_path, dirs


def grep_for_skill_mentions(dirs, max_hits=15):
    hits = []
    for d in dirs:
        returncode, stdout, _ = run([
            "grep", "-rli", "--include=*.md", "skill", str(d),
        ], timeout=20)
        if returncode == 0:
            for line in stdout.splitlines():
                hits.append(line)
                if len(hits) >= max_hits:
                    return hits
    return hits


def deep_scan(binary: str):
    if not binary:
        return {"status": "skipped", "reason": "no reliable binary name to check"}
    binary_path, pkg_dirs = locate_package_dirs(binary)
    if not binary_path:
        return {"status": "not_installed", "binary": binary}
    hits = grep_for_skill_mentions(pkg_dirs) if pkg_dirs else []
    return {
        "status": "installed",
        "binary_path": binary_path,
        "package_dirs": [str(d) for d in pkg_dirs],
        "skill_mention_files": hits,
        "note": "raw hits from installed docs/source — read the most promising "
                "one to learn how this tool actually discovers skills",
    }


def discover_one(name: str, spec: dict):
    result = {"tool": name, "mode": spec["mode"]}
    result["candidates"] = [inspect_dir(Path(c).expanduser()) for c in spec["candidates"]]
    any_exists = any(c["exists"] for c in result["candidates"])

    if spec.get("verify_cmd"):
        returncode, stdout, stderr = run(spec["verify_cmd"], timeout=20)
        result["verify_cmd_result"] = {
            "command": spec["verify_cmd"],
            "returncode": returncode,
            "stdout_tail": stdout.strip()[-2000:],
            "stderr_tail": stderr.strip()[-500:],
        }

    if not any_exists and spec.get("binary"):
        result["deep_scan"] = deep_scan(spec["binary"])

    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tool", action="append", default=None, help="Limit to these known tool names")
    parser.add_argument("--deep-scan-unknown", help="Run just the fallback for a tool not in TOOLS")
    parser.add_argument("--binary", help="Binary name to use with --deep-scan-unknown")
    args = parser.parse_args()

    if args.deep_scan_unknown:
        emit({"tool": args.deep_scan_unknown, "mode": "unknown", "deep_scan": deep_scan(args.binary)})
        return

    names = args.tool or list(TOOLS.keys())
    emit([discover_one(name, TOOLS[name]) for name in names if name in TOOLS])


if __name__ == "__main__":
    main()
