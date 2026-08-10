---
name: skills-sync
description: Use when the user wants to audit or fix how their AI coding agents (Claude Code, Codex, Gemini CLI, Pi, etc.) discover skills — making sure a single repo clone is the source of truth and every tool's skill directory resolves to it via symlinks, instead of duplicated copies drifting apart.
---

# skills-sync

Audits and repairs the setup that lets multiple local AI agents (Claude Code,
Codex, Gemini CLI, Pi/DeepSeek, and any new tool that shows up later) share one
set of skills from a single git-versioned repo clone — no copies, no drift.

For the full design rationale (why state lives where it does, why the tool
table has a "hub_alias" mode, how the Gemini discovery actually happened), see
`references/rationale.md`.

## The target architecture

```
<repo clone>/skills/<name>/        <- the only real copy, git-versioned
        ^
        |  symlink, one per skill
~/.agents/skills/<name>            <- the hub: every tool resolves through here
        ^
        |  symlink, one per skill (most tools)
~/.claude/skills/<name>            <- per-tool dir, if the tool has one
~/.codex/skills/<name>
~/.pi/agent/skills/<name>
        (some tools, like Gemini CLI, read ~/.agents/skills directly as a
        native alias tier and need no per-tool directory at all)
```

Two tiers, not one: the hub exists so a tool needing its own directory
(`~/.claude/skills`, etc.) has one stable thing to point every skill at,
without knowing anything about the repo's location. The repo can move; only
the hub's symlinks need updating.

Skills installed by an external installer (tracked in
`~/.agents/.skill-lock.json`, sourced from other GitHub repos) are a separate
concern — never touch them. They're not part of this repo and don't belong in
it.

## Core principle

Scripts here only inspect and classify, or perform one already-decided,
narrowly-scoped filesystem operation. They **never decide** to overwrite real
content — that always requires a diff shown to the user and their explicit
confirmation. This mirrors youtube-audio-library's split: scripts are
deterministic and cautious, the agent (with the user) makes the judgment
calls.

## Workflow

1. **Locate the repo.** Run `scripts/find_repo.py`. If it reports `not_found`,
   ask the user for the path, or offer `find_repo.py --search` (searches
   `~/code`, `~/dev`, `~/projects`, `~/repos` by default for a git remote
   matching "agent-skills" — pass `--hint` if their remote/repo name differs).
   Once found, the path is remembered in `~/.agents/agent-skills.json` for next
   time — you shouldn't need to re-ask on a healthy machine.
2. **Discover each tool's skill directory.** Run `scripts/discover_tools.py`.
   For tools not in its known table (or whose known candidates don't exist
   despite the tool being installed), it deep-scans the installed
   package/binary for "skill" mentions in shipped docs — read the most
   promising hit yourself to figure out how that tool actually resolves
   skills, then either add it to `discover_tools.py`'s `TOOLS` table (see
   `references/rationale.md` for the two modes) or treat it as unsupported for
   now. Don't guess at a tool's behavior from the mention alone — the doc hit
   is a lead, not a conclusion.
3. **Build the full inventory.** Run
   `scripts/inventory.py --repo-root <path>`. This cross-references every
   repo skill against its hub entry and every `per_skill_symlink`-mode tool's
   entry, classifying each as `missing` / `symlink_ok` / `symlink_wrong` /
   `real_dir_identical` / `real_dir_diverges`. It also flags anything sitting
   in the hub that isn't a repo skill (`hub_extra`), marking lockfile-tracked
   names as `protected` — never propose touching those.
4. **Present a numbered plan.** Group the findings and show the user a
   numbered table of what you'd do — e.g. `1) Link 'jira' into ~/.pi (missing)
   2) Replace ~/.agents/skills/bitbucket (diverges from repo — see diff) 3)
   Leave 'caveman' alone (third-party)`. `symlink_ok` entries need no line at
   all — only report actionable items. Let the user drop/approve items before
   touching anything (see the "Presenting choices" convention below).
5. **Diff before replacing.** For every `real_dir_diverges` entry the user
   approved touching, run `scripts/diff_skill.py --a <existing> --b <repo
   copy> --full` and show the actual diff — not just "they differ" — so the
   user's approval is informed. If a divergent copy has something the repo
   doesn't (like `jira`'s runtime `data/` cache earlier), move that piece into
   the repo copy first (respecting its `.gitignore`) so it survives the
   replace.
6. **Apply.** For each approved item, run `scripts/link_skill.py --target
   <path> --points-to <expected-target>`, adding `--replace` for
   `real_dir_diverges`/`real_dir_identical` or `--relink` for
   `symlink_wrong` — only for the items the user actually approved. Missing
   entries need neither flag.
7. **Report and re-verify.** Summarize what changed, then re-run
   `inventory.py` (and each `hub_alias`-mode tool's `verify_cmd`, e.g. `gemini
   skills list --all`) to confirm the fix actually took. A clean re-run should
   report nothing left to do — this workflow is meant to be idempotent.

## Presenting choices

Number actionable findings so the user can approve with bare numbers ("1 3 4",
or "all") instead of restating each one. Skip anything already `symlink_ok` —
don't make the user wade through a wall of "this one's fine" lines.

## Adding a new tool

Append an entry to `discover_tools.py`'s `TOOLS` table: a `mode`
(`per_skill_symlink` or `hub_alias`), its known `candidates` (skill directory
paths), and, if reliable, a `binary` name for the deep-scan fallback. If it's
`per_skill_symlink`, also add its directory to `inventory.py`'s `TOOL_DIRS`. If
it's `hub_alias`, add a `verify_cmd` if the tool has one (a CLI command that
lists discovered skills) so step 7 can actually confirm the fix worked instead
of taking it on faith.

## Script reference

All scripts print a single JSON object/array to stdout and never prompt
interactively.

- `find_repo.py [--path DIR | --search [--hint TEXT] [--search-root DIR ...]]`
- `discover_tools.py [--tool NAME ...] | [--deep-scan-unknown NAME --binary BIN]`
- `inventory.py --repo-root DIR [--hub-root ~/.agents/skills]`
- `diff_skill.py --a PATH --b PATH [--full]`
- `link_skill.py --target PATH --points-to PATH [--replace] [--relink]`

Requires `git`, `diff`, and (for the deep-scan fallback) `which`/`npm` on PATH.
No non-stdlib Python dependencies.
