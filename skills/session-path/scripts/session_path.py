#!/usr/bin/env python3
"""Resolve local session-transcript paths for supported coding agents."""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path


def codex_roots() -> list[Path]:
    home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()
    return [home / "sessions", home / "archived_sessions"]


def claude_roots() -> list[Path]:
    home = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")).expanduser()
    return [home / "projects"]


def transcript_files(agent: str) -> list[Path]:
    files: list[Path] = []
    if agent in ("codex", "auto"):
        for root in codex_roots():
            if root.is_dir():
                files.extend(path for path in root.rglob("*.jsonl") if path.is_file())
    if agent in ("claude-code", "auto"):
        for root in claude_roots():
            if root.is_dir():
                # Sessions sit at projects/<project>/<id>.jsonl; subagent
                # transcripts live deeper, under <id>/subagents/, and are skipped.
                files.extend(path for path in root.glob("*/*.jsonl") if path.is_file())
    return files


def claude_project_dir(cwd: Path) -> Path:
    # Claude Code names each project directory after its launch directory, with
    # every non-alphanumeric character replaced by "-".
    return claude_roots()[0] / re.sub(r"[^A-Za-z0-9]", "-", str(cwd.resolve()))


def files_containing(needle: bytes, paths: list[Path]) -> list[Path]:
    matches: list[Path] = []
    for path in paths:
        try:
            if needle in path.read_bytes():
                matches.append(path)
        except OSError:
            continue
    return matches


def claude_transcripts_for(cwd: Path) -> list[Path]:
    project_dir = claude_project_dir(cwd)
    if project_dir.is_dir():
        return [path for path in project_dir.glob("*.jsonl") if path.is_file()]
    # Very long paths get a shortened directory name; fall back to the cwd field
    # each transcript entry records.
    needle = json.dumps({"cwd": str(cwd.resolve())}, separators=(",", ":"))[1:-1].encode()
    return files_containing(needle, transcript_files("claude-code"))


def agent_for(path: Path) -> str:
    parts = path.parts
    return "codex" if ".codex" in parts else "claude-code"


def result(
    *,
    status: str,
    agent: str,
    confidence: str | None = None,
    path: Path | None = None,
    candidates: list[Path] | None = None,
    message: str | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {"status": status, "agent": agent}
    if confidence:
        payload["confidence"] = confidence
    if path:
        payload["path"] = str(path.resolve())
    if candidates:
        payload["candidates"] = [str(candidate.resolve()) for candidate in candidates]
    if message:
        payload["message"] = message
    return payload


def resolve_explicit(agent: str, session: str) -> dict[str, object]:
    supplied_path = Path(session).expanduser()
    if supplied_path.is_file():
        return result(
            status="resolved",
            agent=agent_for(supplied_path) if agent == "auto" else agent,
            confidence="exact",
            path=supplied_path,
        )

    matches = [
        path
        for path in transcript_files(agent)
        if session in path.name or path.stem == session
    ]
    if len(matches) == 1:
        return result(status="resolved", agent=agent_for(matches[0]), confidence="exact", path=matches[0])
    if len(matches) > 1:
        return result(
            status="ambiguous",
            agent=agent,
            candidates=sorted(matches),
            message="The supplied session identifier matches more than one transcript.",
        )
    return result(
        status="not_found",
        agent=agent,
        message="No transcript matches the supplied session identifier or path.",
    )


def resolve_current(agent: str, cwd: Path) -> dict[str, object]:
    session_environment = {
        "codex": "CODEX_SESSION_ID",
        "claude-code": "CLAUDE_CODE_SESSION_ID",
    }
    agents = [agent] if agent != "auto" else ["codex", "claude-code"]
    for candidate_agent in agents:
        session_id = os.environ.get(session_environment[candidate_agent])
        if session_id:
            exact = resolve_explicit(candidate_agent, session_id)
            if exact["status"] == "resolved":
                return exact

    matches: list[Path] = []
    if agent in ("codex", "auto"):
        matches.extend(files_containing(str(cwd.resolve()).encode(), transcript_files("codex")))
    if agent in ("claude-code", "auto"):
        matches.extend(claude_transcripts_for(cwd))

    if not matches:
        return result(
            status="not_found",
            agent=agent,
            message="No transcript matches the requested working directory.",
        )

    matches.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    newest = matches[0]
    # A timestamp match is useful but remains a heuristic: two active agents can
    # work in the same directory. Report that limitation rather than guessing.
    if len(matches) > 1 and matches[1].stat().st_mtime == newest.stat().st_mtime:
        return result(
            status="ambiguous",
            agent=agent,
            candidates=matches[:10],
            message="Multiple matching transcripts have the same latest modification time.",
        )
    return result(status="resolved", agent=agent_for(newest), confidence="inferred", path=newest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", choices=["auto", "codex", "claude-code"], default="auto")
    parser.add_argument("--session", help="Exact transcript path or agent session identifier")
    parser.add_argument("--current", action="store_true", help="Infer the newest transcript for --cwd")
    parser.add_argument("--cwd", type=Path, default=Path.cwd(), help="Working directory used by --current")
    parser.add_argument("--path-only", action="store_true", help="Print only a resolved path")
    args = parser.parse_args()

    if bool(args.session) == bool(args.current):
        parser.error("choose exactly one of --session or --current")

    payload = (
        resolve_explicit(args.agent, args.session)
        if args.session
        else resolve_current(args.agent, args.cwd)
    )
    if args.path_only:
        if payload.get("status") != "resolved":
            return 2
        print(payload["path"])
    else:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if payload.get("status") == "resolved" else 2


if __name__ == "__main__":
    raise SystemExit(main())
