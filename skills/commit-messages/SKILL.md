---
name: commit-messages
description: Create or propose git commit messages for code changes. Use when the user asks to commit, asks for commit message options, or needs help writing a Conventional Commit. Reads repo-local rules from AGENTS.md and applies them when present.
---

# Commit Messages

Use this skill when proposing or creating git commits.

## Workflow

1. Read staged changes or the intended change set before writing the message.
2. Read repo-local rules from `AGENTS.md` if present.
3. If the user did not give the exact commit message, propose 3 strong variants and stop for user selection.
4. If the repo requires Jira or issue suffix rules, apply them.
5. When the repo requires `AI_MODE=1` for commit / push / hooks, preserve that behavior.

## Message Shape

Use Conventional Commits:

```text
<type>[optional scope]: <description> [optional issue key]

[optional body]
```

## Rules

- Keep the subject anchored to the main outcome, not a file list.
- Use lowercase imperative style and no trailing period.
- Use a one-line commit when the change is small and obvious.
- Add a short body when the change is non-trivial, spans multiple areas, or needs rationale.
- Body should explain outcome and reason, not narrate implementation steps.
- Scope is optional. Use it only when it adds signal.
- Prefer specific subjects over vague ones like `update ui` or `minor fixes`.

## Types

- `feat`: new visible capability
- `fix`: corrected behavior
- `refactor`: internal restructuring without intended behavior change
- `perf`: performance-focused change
- `docs`, `test`, `chore`, `ci`, `style`: conventional meaning

## Output

When proposing options, provide 3 variants with distinct strengths, for example:
- most direct
- most product/outcome oriented
- most technical/scope specific

Do not create or amend the commit until the user selects one variant or provides the exact final message.

When the user already gave the exact message, use it unless it conflicts with explicit repo policy.
