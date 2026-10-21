---
name: codex-delegate
description: "Turn this Claude Code session into an orchestrator whose child sessions hand the heavy coding to Codex CLI, so implementation runs on the Codex subscription while Claude plans and reviews."
disable-model-invocation: true
---

# Codex Delegate

This session becomes the **orchestrator**. Each coding task goes to a child session that acts as a **supervisor**: Codex (`codex exec`, run by `scripts/codex-delegate.mjs`) writes the code, and the supervisor verifies it, fixes small things and reports back. Codex tokens pay for exploring, editing and iterating on tests; Claude tokens pay for planning and review.

Children cannot load this skill, so every brief carries what they need. Resolve the script's absolute path once, from this skill's base directory: `<base>/scripts/codex-delegate.mjs`.

## Pick a route per task

- **Child route**, the default: the task deserves its own session, one you can open, talk to and order to commit.
- **Direct route**: a task where a child adds nothing; this session launches Codex itself.
- **Small change** (a few lines): make it here, or have a child make it without Codex. The handoff costs more than the change.

## Child route

1. **Write the brief.** Put the task first: what to do, the files or area, what done means, and the specs or docs to read. When the task calls for a Codex model or reasoning effort other than the Codex config's (say, a lower effort for mechanical work), name them in the task. Append [references/child-brief.md](references/child-brief.md) below it, with `<script>` replaced by the absolute path. Done when the brief is self-contained: a fresh session with no view of this conversation could act on it.
2. **Start the child** with `start_session`: `context: "fresh"` and a cheaper `model` (Sonnet), since supervising does not need the orchestrator's model. Follow the user's rules on worktrees and running children one at a time; the script's lock refuses a second Codex run in the same checkout regardless.
3. **Read each report.** A report of `waiting on Codex <slug>` is a heartbeat: let it pass without a reply and wait for the next one. A final report gets a **criteria review**: does the change meet the task and the spec, and is the diff the size and shape you expected. The supervisor already ran the mechanical checks, so read their results instead of running them again.
4. **Send corrections and commit orders** to the child, as with any child session. The child decides whether a correction is small enough to make itself or goes back to Codex with `--resume`.

## Direct route

1. Write a self-contained prompt for Codex to a file in your scratchpad. Codex reads the repo's `AGENTS.md`, and nothing else from this session: copy in what it needs from this conversation and from local instruction files such as `CLAUDE.local.md`.
2. Launch it with the Bash tool and `run_in_background: true`:
   `node <script> --slug <slug> --repo <repo> --prompt-file <file> [--model <m>] [--effort <level>]`
3. End the turn. Claude Code wakes this session when Codex exits. Until then the checkout is Codex's: read and answer questions freely, and save edits for after the notification.
4. On the notification, review `git diff` and run the project's checks before reporting. For another round, run the same slug with `--resume`.

## Script behavior

- It refuses a dirty checkout unless given `--allow-dirty`; with it, the summary lists only the files Codex changed.
- Codex runs with `--sandbox workspace-write` (override with `CODEX_FLAGS`) and gets rules appended to the prompt: leave commits and branch changes to the caller, end with a short summary.
- Codex's environment drops `CLAUDE_CODE_MESSAGING_*`, so the code it runs cannot message the Claude session.
- `--model` and `--effort` override the Codex config's `model` and `model_reasoning_effort` for one run.
- The summary ends with a usage block: `Context:` (how full Codex's context was on its last call), `5h Session:` and `Weekly:` (the account's rate-limit windows). The script reads them from Codex's session record, so they cost no Codex tokens, and keeps the run's token counts in `meta.json`. The limits cover the whole Codex account, including use outside this delegation.
- `--resume` continues the Codex session of the latest run of that slug in the same repo, so a round of fixes keeps the context of the first.
- Each run writes `result.md`, `codex.log` and `meta.json` to `~/.codex-delegate/<slug>-<timestamp>/`; the printed summary points to them.
- It looks for `codex` on `PATH`, then in `Codex.app`; set `CODEX_BIN` to override.
