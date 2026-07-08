---
name: bitbucket
description: Use when the user asks to list, inspect, comment on, approve, or merge Bitbucket pull requests, PR comments, reviewers, or repository info. Uses Bitbucket REST API 2.0 with Repository Access Tokens (Bearer auth).
---

# Bitbucket

Use this skill for Bitbucket Cloud operations: reading PR details, listing/posting PR comments, approving PRs, merging PRs, and listing open PRs.

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
3. Save the token (format `ATCTT3x...`) in `./.bitbucket-token`

Workspace-level tokens are a Premium feature — use repo-level tokens.

App Passwords (Basic Auth) are **deprecated** and will be removed July 28, 2026. This skill uses only Bearer auth.

Do not validate credentials manually — the scripts handle it.

### Missing token: offer to create it

Before running any script, check whether `./.bitbucket-token` (repo-local) or `~/.bitbucket-env` (global fallback) exists. If neither exists:

1. Tell the user this repo has no Bitbucket credentials yet, so the skill can't run.
2. Derive `<workspace>` and `<repo>` from `git remote get-url origin` (see below) and include the token creation link and required scopes directly in your response:
   - Link: `https://bitbucket.org/<workspace>/<repo>/admin/access-tokens`
   - Scopes: **Repositories: Read**, **Pull requests: Read**, **Pull requests: Write**
3. Ask if they want you to create `./.bitbucket-token` now with a placeholder template.
4. If they agree, write `./.bitbucket-token` with this exact template (substituting `<workspace>`/`<repo>`):
   ```
   # Bitbucket Repository Access Token for <repo>

   # Created at: https://bitbucket.org/<workspace>/<repo>/admin/access-tokens

   # Scopes: Repositories: Read, Pull requests: Read+Write

   # Replace with your actual token:

   BITBUCKET_API_TOKEN=
   ```
5. Tell the user to open the link, create the token with the scopes above, and paste it after `BITBUCKET_API_TOKEN=` before retrying.

### Keep `.bitbucket-token` out of git

Whenever `./.bitbucket-token` exists in a repo — whether you just created it or it was already there — verify it's actually ignored: run `git check-ignore ./.bitbucket-token`. **Never add it to the repo's own `.gitignore`** — this is personal, experimental tooling that teammates won't recognize, and the entry would need explaining to everyone who clones the repo. If it isn't ignored by anything, tell the user and suggest adding it to their personal global gitignore instead (`git config --get core.excludesfile`, creating one if needed).
6. Tell the user to open the link, create the token with the scopes above, and paste it after `BITBUCKET_API_TOKEN=` before retrying.

## Core Rules

- Use the bundled helper scripts in `scripts/`
- Always use `bitbucket-api.sh` for raw API calls
- Workspace and repo_slug are auto-detected from git remote (`git remote get-url origin`)
- Parse JSON with `/usr/bin/jq` and present concise output. Never dump raw JSON unless asked.
- Never print secrets or echo auth environment variables.
- Prefer read before write. Confirm before posting comments or merging.
- When mentioning PRs or comments to the user, render clickable Markdown links.

## Deriving workspace and repo from git remote

When no workspace/repo is specified, extract them from `git remote get-url origin`:
- `git@bitbucket.org:your-workspace/your-repo.git` → workspace=`your-workspace`, repo=`your-repo`
- `https://your-username@bitbucket.org/your-workspace/your-repo.git` → workspace=`your-workspace`, repo=`your-repo`
- `https://bitbucket.org/your-workspace/your-repo` → same

## Fast Paths

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

## Common API Patterns

- PR details:
  `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}`
- PR comments (all, including inline):
  `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/comments?pagelen=100`
- PR activity (events + comments timeline):
  `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests/{id}/activity`
- List open PRs:
  `bitbucket-api.sh GET /2.0/repositories/{workspace}/{repo}/pullrequests?state=OPEN&pagelen=50`

## Response Rules

- Render PR URLs as Markdown links.
- For inline comments, show the file path and line number prominently.
- Group inline comments by file when listing multiple.
- For general comments (no `inline` field), label them clearly.
- Show author and date for each comment.
- If a comment is a reply (has `parent.id`), indicate the thread context.
- For merge/approve, report the PR title and resulting commit hash.
