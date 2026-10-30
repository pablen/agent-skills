---
name: commit-messages
description: Write Conventional Commit messages when the user asks to commit or needs help with a commit message.
---

# Commit messages

## Workflow

1. Read the staged diff or intended changes and the repo's `AGENTS.md`.
2. If the repo requires a Jira or issue suffix, append the key in brackets:
   `[HIBA-58]`.
3. When the repo requires `AI_MODE=1` for commit / push / hooks, preserve that behavior.
4. When asked to commit, create the commit within the requested scope without asking for message approval. Report its hash and subject.

For message-only requests, return one recommended message. Offer alternatives only when asked.

## Message format

```text
<type>[optional scope]: <description> [optional issue key]

[optional body]
```

- Write the subject and any body in English, unless the user explicitly requests another language.
- Describe the main outcome in a specific, lowercase imperative subject, with no trailing period.
- Add a scope when it clarifies which part of the code changed.
- A subject is enough for small, obvious changes. Add a short body when the change spans several areas or needs explanation.
- Use the body to explain what changed and why.

## Types

- `feat`: new functionality
- `fix`: corrected behavior
- `refactor`: internal restructuring without intended behavior changes
- `perf`: performance improvement
- `docs`, `test`, `chore`, `ci`, `style`: use their Conventional Commits meanings
