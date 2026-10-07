---
name: session-path
description: "Resolve the local transcript path for a Codex or Claude Code session. Use when a user asks where a coding-agent session is stored, needs its absolute path, or wants to hand a transcript to another tool."
disable-model-invocation: true
---

# Session Path

Return a local transcript path without reading or changing transcript content.

Run the resolver with an explicit agent when it is known:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/session_path.py" --agent claude-code --current --cwd "$PWD"
```

The script lives in this skill's directory, not the project's. In Claude Code,
`${CLAUDE_SKILL_DIR}` points to it; in other agents, resolve
`scripts/session_path.py` against the skill's base directory.

Use `--session <id-or-path>` when the caller provides a session identifier or a
known transcript path. This reports `exact` confidence. `--current` also reports
`exact` when the active agent exposes its session ID through the environment;
otherwise it falls back to a timestamp-based inference.

For an unspecified agent, use `--agent auto`. The resolver returns JSON:

- `confidence: exact`: an explicit path or session identifier resolved uniquely.
- `confidence: inferred`: the most recent transcript for the requested working
  directory. State that this is an inference.
- `status: ambiguous` or `not_found`: return the candidates or the diagnostic;
  do not choose one arbitrarily.

Supported adapters:

- `codex`: `$CODEX_HOME/sessions` and `$CODEX_HOME/archived_sessions`
  (defaults to `~/.codex`). Session ID from `CODEX_SESSION_ID`.
- `claude-code`: `$CLAUDE_CONFIG_DIR/projects/<project>/<id>.jsonl` (defaults
  to `~/.claude`), where `<project>` is the launch directory with every
  non-alphanumeric character replaced by `-`. Session ID from
  `CLAUDE_CODE_SESSION_ID`. Subagent transcripts under `<id>/subagents/` are
  not sessions and are skipped.

The storage layout is agent-specific and may change. Add another adapter only
after verifying it against a real local installation. Do not delete, move, or
archive transcripts as part of lookup.
