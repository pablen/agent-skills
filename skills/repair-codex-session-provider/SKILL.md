---
name: repair-codex-session-provider
description: Repair all saved Codex sessions whose recorded model provider no longer exists. Audit the session files and local indexes, back them up, migrate the stale records to OpenAI, and validate the result. Use only when explicitly asked to repair unavailable session providers.
---

# Repair Codex Session Provider

Repair every session whose saved `model_provider` refers to a removed provider, such as `deepseek`, so each can resume with the user's active OpenAI model configuration.

Do not use this to change a user's current default model, remove a valid third-party provider, or repair only a hand-picked session when the user asked for a full sweep.

## Workflow

1. Read `~/.codex/config.toml` to identify the user's current default model and reasoning effort. Do not change that file unless the user separately asks.
2. Build a candidate list by reading the first JSONL record from every file under `~/.codex/sessions/`. Keep records whose `type` is `session_meta` and whose `payload.model_provider` is neither `openai` nor declared in a `[model_providers.<name>]` block in the current config. Do not treat a valid configured provider as stale.
3. Check the local indexes too. For each candidate ID, query `~/.codex/state_5.sqlite` (`threads`) and `~/.codex/sqlite/codex-dev.db` (`local_thread_catalog`). Also include index-only stale records whose provider is unavailable, even if the matching JSONL is missing.
4. Report the candidate count, IDs, providers, and intended destination (`openai`). Get confirmation before the write phase unless the user already explicitly authorized repairing every stale session in this request.
5. Back up every JSONL that will change beside the original, using `<session>.jsonl.bak-YYYYMMDD-HHMMSS`. If either SQLite index will change, create one consistent timestamped backup of each database with SQLite's `.backup` command.
6. For each candidate JSONL, change only the first session-metadata occurrence of `"model_provider":"<old>"` to `"model_provider":"openai"`. The same string can appear in later conversation records, tool schemas, or pasted content. Leave those records untouched.
7. For each matching row in `state_5.sqlite`, set `model_provider` to `openai` and align `model` plus `reasoning_effort` with the current global configuration. For each matching local catalog row, set only `model_provider` to `openai`. Update exact candidate IDs, never every row for a provider.
8. Parse every changed JSONL. Confirm that the first record and each applicable SQLite index row now report `openai`, and that every expected backup exists. Report skipped records separately with their reason.
9. Tell the user to fully quit and reopen Codex before opening the repaired sessions. Report the repaired and skipped counts, backup paths, and configured default model.

## Safety

- Do not use a broad search-and-replace across the session. Replace exactly one occurrence, the first metadata occurrence.
- Do not assume that editing the JSONL is enough. A stale SQLite index can keep producing the same missing-provider error.
- If a session file is malformed, already uses `openai`, or has an unexpected first record, skip it and report why. Do not block the rest of the sweep.
- Never print credentials or unrelated session contents.
- This is a local application-state change. Request approval when the environment requires it, even after the user has identified the session.
