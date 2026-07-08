# agent-skills

Personal skills for coding agents (Claude Code, Codex, etc.), installable via [skills.sh](https://www.skills.sh/).

## Install

```sh
npx skills add pabloenrici/agent-skills
```

Or a single skill:

```sh
npx skills add https://github.com/pabloenrici/agent-skills/tree/main/skills/bitbucket
```

## Skills

- **bitbucket** — List, inspect, comment on, approve, or merge Bitbucket pull requests via the REST API (Repository Access Token auth).
- **commit-messages** — Draft Conventional Commit messages, respecting repo-local rules from `AGENTS.md` when present.
- **frontend-code-quality-setup** — Audit and apply a standard code-quality baseline (VSCode, package manager, dependency policy, git hooks, lint-staged, `.gitignore`, agent files) to a frontend project.
- **frontend-ready-check** — Check whether a frontend task is actually ready to implement by cross-referencing frontend usage, backend/service support, and related tracker work.
- **jira** — List, search, inspect, create, comment on, and transition Jira issues via the REST API.

## Credentials

Each skill documents its own credential setup in its `SKILL.md` (Bitbucket and Jira both use per-repo/per-user tokens read from a local file — never commit those files).
