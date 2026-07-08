---
name: bitbucket
description: Use for Bitbucket pull requests (comments, reviewers, approve, merge) and pipelines (list, steps, logs).
---

# Bitbucket

Use this skill for Bitbucket Cloud operations: reading PR details, listing/posting PR comments, approving PRs, merging PRs, listing open PRs, listing pipelines, inspecting pipeline runs, and reading step logs.

## Credentials

Uses a single **Repository Access Token** (Bearer auth) — one token per repo.

Token lookup order:
1. `./.bitbucket-token` (repo-local, **recommended** — gitignore it)
2. `~/.bitbucket-env` (global fallback)

In either file:
```
BITBUCKET_API_TOKEN=ATCTT3x...
```

### Creating a token

1. Go to `https://bitbucket.org/<WORKSPACE>/<REPO>/admin/access-tokens`
2. Create token with scopes:
   - **Repositories: Read**
   - **Pull requests: Read**
   - **Pull requests: Write** (needed for approve, merge, comment)
   - **Pipelines: Read** (needed for pipeline operations)
3. Save the token (format `ATCTT3x...`) in `./.bitbucket-token`

Workspace-level tokens are a Premium feature — use repo-level tokens.

App Passwords (Basic Auth) are **deprecated** and will be removed July 28, 2026. This skill uses only Bearer auth.

Do not validate credentials manually — the scripts handle it.

### Missing token: offer to create it

Before running any script, check whether `./.bitbucket-token` (repo-local) or `~/.bitbucket-env` (global fallback) exists. If neither exists:

1. Tell the user this repo has no Bitbucket credentials yet, so the skill can't run.
2. Derive `<workspace>` and `<repo>` from `git remote get-url origin` (see below) and include the token creation link and required scopes directly in your response:
   - Link: `https://bitbucket.org/<workspace>/<repo>/admin/access-tokens`
   - Scopes: **Repositories: Read**, **Pull requests: Read**, **Pull requests: Write**, **Pipelines: Read**
3. Ask if they want you to create `./.bitbucket-token` now with a placeholder template.
4. If they agree, write `./.bitbucket-token` with this exact template (substituting `<workspace>`/`<repo>`):
   ```
   # Bitbucket Repository Access Token for <repo>

   # Created at: https://bitbucket.org/<workspace>/<repo>/admin/access-tokens

   # Scopes: Repositories: Read, Pull requests: Read+Write, Pipelines: Read

   # Replace with your actual token:

   BITBUCKET_API_TOKEN=
   ```
5. Tell the user to open the link, create the token with the scopes above, and paste it after `BITBUCKET_API_TOKEN=` before retrying.

### Keep `.bitbucket-token` out of git

Whenever `./.bitbucket-token` exists in a repo — whether you just created it or it was already there — verify it's actually ignored: run `git check-ignore ./.bitbucket-token`. **Never add it to the repo's own `.gitignore`** — this is personal, experimental tooling that teammates won't recognize, and the entry would need explaining to everyone who clones the repo. If it isn't ignored by anything, tell the user and suggest adding it to their personal global gitignore instead (`git config --get core.excludesfile`, creating one if needed).

## Core Rules

- Use the bundled helper scripts in `scripts/`
- Use `bitbucket-api.sh` for all API calls (it sends `Accept: application/json` and handles Bearer auth)
- For the pipeline step logs endpoint (which returns text/plain and rejects JSON accept), use `bitbucket-pipeline-logs.sh`
- Workspace and repo_slug are auto-detected from git remote (`git remote get-url origin`)
- Parse JSON with `/usr/bin/jq` and present concise output. Never dump raw JSON unless asked.
- Never print secrets or echo auth environment variables.
- Prefer read before write. Confirm before posting comments or merging.
- When mentioning PRs, comments, or pipelines to the user, render clickable Markdown links.

## Deriving workspace and repo from git remote

When no workspace/repo is specified, extract them from `git remote get-url origin`:
- `git@bitbucket.org:your-workspace/your-repo.git` → workspace=`your-workspace`, repo=`your-repo`
- `https://your-username@bitbucket.org/your-workspace/your-repo.git` → workspace=`your-workspace`, repo=`your-repo`
- `https://bitbucket.org/your-workspace/your-repo` → same

## Fast Paths — Pull Requests

### "PR comments" / "comentarios del PR #N"

```bash
scripts/bitbucket-pr-comments.sh <workspace> <repo_slug> <pr_id>
```
Outputs all non-deleted comments with author, date, file+line (inline) or "general comment".

### "PR details" / "info del PR #N"

```bash
scripts/bitbucket-pr.sh <workspace> <repo_slug> <pr_id>
```

### "PRs abiertos" / "open PRs"

```bash
scripts/bitbucket-my-prs.sh <workspace> <repo_slug>
```

### "Aprobar PR #N"

```bash
scripts/bitbucket-pr-approve.sh <workspace> <repo_slug> <pr_id>
```
Requires Pull requests: Write scope on the token.

### "Mergear PR #N"

```bash
scripts/bitbucket-pr-merge.sh <workspace> <repo_slug> <pr_id> [merge_strategy]
```
`merge_strategy`: `merge_commit` (default) | `squash` | `fast_forward`

### "Comentar en PR #N"

```bash
scripts/bitbucket-pr-comment.sh <workspace> <repo_slug> <pr_id> "<text>" [parent_comment_id]
```
Omit `parent_comment_id` for a general comment; include it to reply to a thread.

## Fast Paths — Pipelines

### "Ver pipelines fallidos" / "último pipeline fallido"

```bash
scripts/bitbucket-pipelines.sh <workspace> <repo_slug> FAILED
```
Omit `status` to list all pipelines regardless of status. Optional 4th arg `pagelen` (default 10). Outputs build number, status, branch, commit, created date, and UUID (needed for the detail/logs commands below).

### "Ver detalle de pipeline"

```bash
scripts/bitbucket-pipeline.sh <workspace> <repo_slug> <pipeline_uuid>
```
Prints the pipeline summary plus its steps, each with status, duration, and step UUID (needed for `bitbucket-pipeline-logs.sh`).

### "Ver logs de un step"

```bash
scripts/bitbucket-pipeline-logs.sh <workspace> <repo_slug> <pipeline_uuid> <step_uuid>
```
Prints step metadata header followed by full log output. Uses plain text endpoint (not JSON), so it calls curl directly instead of `bitbucket-api.sh`.

## Common API Patterns

### Pull Requests

- PR details: `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}`
- PR comments (all, including inline): `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/comments?pagelen=100`
- PR activity (events + comments timeline): `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/activity`
- List open PRs: `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests?state=OPEN&pagelen=50`

### Pipelines

- List pipelines: `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pipelines/?status=FAILED&pagelen=10&sort=-created_on` (query param is `status`, not `state` — `state`/`result` are silently ignored and return unfiltered results)
- Pipeline details: `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pipelines/{uuid}`
- Pipeline steps: `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pipelines/{uuid}/steps/`
- Step logs (text/plain, use `bitbucket-pipeline-logs.sh`): `bitbucket-pipeline-logs.sh <workspace> <repo> <pipeline_uuid> <step_uuid>`

## Response Rules

- Render PR and pipeline URLs as Markdown links.
- For inline comments, show the file path and line number prominently.
- Group inline comments by file when listing multiple.
- For general comments (no `inline` field), label them clearly.
- Show author and date for each comment and pipeline.
- If a comment is a reply (has `parent.id`), indicate the thread context.
- For merge/approve, report the PR title and resulting commit hash.
- For pipelines, highlight the failed step and show the actual error from logs (skip setup/bootstrap noise).
