# Commit Messages

Use this guide only when proposing or creating a commit.

## Defaults

- Follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
- Read `git diff --staged` first and write the commit around the main outcome.
- Before committing, present 3 strong message variants and let the user choose, unless they already gave the exact message.
- Prefer a concrete subject that names the main affected area when useful.
- Use a short body for any change that is not tiny and obvious.

## Structure

```text
<type>[optional scope]: <description> [ISSUE-KEY]

[optional body]

[optional footer(s)]
```

## Subject

- Start lowercase, use imperative mood, and do not end with a period.
- Keep it concise, but prefer clarity over a hard character limit.
- Scope is optional. Use it when it adds signal, such as `auth`, `router`, `calendar`, `account-settings`, `version-check`, or `e2e`.
- Anchor the subject to the primary outcome or flow being changed, not just the first shared module touched.
- Name the screen, form, modal, flow, entity, or shared module when that is the clearest anchor.
- Avoid generic subjects like `update ui`, `adjust form`, `improve flow`, or `minor fixes`.

## Body

- Omit the body only when the subject is self-sufficient.
- Prefer 2-4 short lines.
- Explain outcome and reason, not implementation steps, file lists, or internal narration.

## Types

- `feat`: new user-visible capability or workflow step
- `fix`: corrected or clarified behavior
- `refactor`: internal restructuring with equivalent behavior
- `perf`: primary goal is performance
- `docs`, `test`, `chore`, `ci`, `style`: use their conventional meaning

## Jira

- When a Jira issue exists, append `[ISSUE-KEY]` to the subject.
- If the user gives only a number, assume `<PROJECT_KEY>-<number>` unless told otherwise.
- If the user asks for a commit without a Jira key and does not explicitly say there is no task, ask before committing.
