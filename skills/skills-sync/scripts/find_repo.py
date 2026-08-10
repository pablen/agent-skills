#!/usr/bin/env python3
"""Locate the agent-skills repo clone on this machine and remember it.

Resolution order:
  1. --path, if given: verify and save it.
  2. The saved path in the state file (~/.agents/agent-skills.json), if valid.
  3. The default (~/code/agent-skills), if valid.
  4. --search <hint> [--search-root DIR ...]: walk the given roots (default
     ~/code, ~/dev, ~/projects, ~/repos) up to a shallow depth looking for a
     git repo whose origin remote contains <hint> (default: "agent-skills").

A repo is "valid" if it's a git working tree with a skills/ subdirectory.
Never guesses silently past what's asked — if nothing is found, reports
status "not_found" and lets the agent ask the user or try --search.

Usage:
  find_repo.py                      # try saved state, then the default path
  find_repo.py --path <dir>         # verify and remember an explicit path
  find_repo.py --search [--hint agent-skills] [--search-root DIR ...]
"""
import argparse
from pathlib import Path

from common import emit, load_state, run, save_state

DEFAULT_PATH = Path.home() / "code" / "agent-skills"
DEFAULT_SEARCH_ROOTS = ["~/code", "~/dev", "~/projects", "~/repos"]
DEFAULT_SEARCH_DEPTH = 2


def is_valid_repo(path: Path) -> bool:
    return path.is_dir() and (path / ".git").exists() and (path / "skills").is_dir()


def describe(path: Path, source: str) -> dict:
    returncode, stdout, _ = run(["git", "-C", str(path), "remote", "get-url", "origin"])
    remote = stdout.strip() if returncode == 0 else None
    skills = sorted(p.name for p in (path / "skills").iterdir() if p.is_dir())
    return {
        "status": "ok",
        "path": str(path.resolve()),
        "source": source,
        "remote": remote,
        "skills": skills,
    }


def search(roots, hint: str, max_depth: int):
    candidates = []
    for root_str in roots:
        root = Path(root_str).expanduser()
        if not root.is_dir():
            continue
        candidates.extend(_walk_git_dirs(root, max_depth))

    matches = []
    for git_dir in candidates:
        repo_path = git_dir.parent
        returncode, stdout, _ = run(["git", "-C", str(repo_path), "remote", "get-url", "origin"])
        if returncode == 0 and hint.lower() in stdout.strip().lower():
            matches.append(repo_path)
    return matches


def _walk_git_dirs(root: Path, max_depth: int, depth: int = 0):
    if depth > max_depth:
        return
    try:
        entries = list(root.iterdir())
    except PermissionError:
        return
    for entry in entries:
        if not entry.is_dir():
            continue
        if entry.name == ".git":
            yield entry
            continue
        if entry.name.startswith("."):
            continue
        yield from _walk_git_dirs(entry, max_depth, depth + 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", help="Verify and remember this exact path")
    parser.add_argument("--search", action="store_true", help="Search --search-root(s) for a matching git remote")
    parser.add_argument("--hint", default="agent-skills", help="Substring to match in the remote URL (default: agent-skills)")
    parser.add_argument("--search-root", action="append", default=None)
    args = parser.parse_args()

    if args.path:
        path = Path(args.path).expanduser()
        if not is_valid_repo(path):
            emit({"status": "invalid", "path": str(path), "error": "not a git repo with a skills/ directory"})
            return
        save_state(repo_path=str(path.resolve()))
        emit(describe(path, source="explicit"))
        return

    if args.search:
        roots = args.search_root or DEFAULT_SEARCH_ROOTS
        matches = search(roots, args.hint, DEFAULT_SEARCH_DEPTH)
        valid = [p for p in matches if is_valid_repo(p)]
        if not valid:
            emit({"status": "not_found", "searched": roots, "hint": args.hint})
            return
        if len(valid) > 1:
            emit({"status": "ambiguous", "candidates": [str(p) for p in valid]})
            return
        save_state(repo_path=str(valid[0].resolve()))
        emit(describe(valid[0], source="search"))
        return

    state = load_state()
    saved = state.get("repo_path")
    if saved and is_valid_repo(Path(saved)):
        emit(describe(Path(saved), source="state"))
        return

    if is_valid_repo(DEFAULT_PATH):
        save_state(repo_path=str(DEFAULT_PATH.resolve()))
        emit(describe(DEFAULT_PATH, source="default"))
        return

    emit({
        "status": "not_found",
        "checked": [saved, str(DEFAULT_PATH)],
        "hint": "ask the user for the path, or retry with --search",
    })


if __name__ == "__main__":
    main()
