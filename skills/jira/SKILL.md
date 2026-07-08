---
name: jira
description: Use for Jira issues (search, create, comment, transition), boards, sprints, and JQL queries.
model: haiku
---

# Jira

Use this skill for Jira Cloud work such as listing assigned issues, running JQL searches, reading issue details, posting comments, changing transitions, and inspecting boards or sprints.

For design rationale and tradeoffs, read `references/rationale.md` only when changing this skill or debating its workflow.

## Core Rules

- Prefer bundled helper scripts in `scripts/`: `jira-api.sh` for generic REST, `jira-transition.sh` for status changes, and the narrow wrappers for frequent reads.
- For writes that need entity resolution, prefer the bundled resolvers and creators over ad hoc REST payload assembly.
- Use Jira REST only through those scripts unless there is a specific reason not to.
- Default to happy-path execution: run the single command that should answer the request, then inspect the failure only if it errors.
- When transitioning an issue to `Done`, require a worklog value before sending the request. If the user did not specify it, ask for it or propose `1h` as the default, and wait for confirmation.
- Never send a transition to `Done` without including the worklog in the same transition payload.
- When creating or editing Jira issues or comments, write in Spanish by default unless the user explicitly asks for another language.
- Write issue descriptions and comments in a concise, direct style. Avoid ceremonial framing, generic filler, and excessive narrative.
- For bug reports, include the suspected failing area or offending code path only when it materially helps debugging. Keep it short and concrete.
- This skill is global. Do not assume a Jira project unless the active context already provides one, for example in a repo `AGENTS.md`.
- Do not validate `JIRA_URL`, `JIRA_EMAIL`, and `JIRA_TOKEN` separately. `jira-api.sh` already does that.
- Do not inspect repo context for Jira-only requests.
- Do not run auxiliary commands such as `pwd` when they do not affect the answer.
- Parse JSON with `jq` and present concise output. Do not dump raw JSON unless asked.
- When mentioning issues or comments to the user, prefer clickable Markdown links to Jira browser pages.
- Never print secrets or echo auth environment variables.
- For writes, prefer a read first when it helps confirm the target state or transition.
- For common status changes, use `jira-transition.sh` instead of reading transitions first. It fast-paths stable workflow ids and falls back to live lookup when needed.

## Fast Paths

### "Mis tasks"

Run exactly:

`scripts/jira-my-tasks.sh [PROJECT]`

Behavior:
- Uses the explicit `PROJECT` argument when present
- Without `PROJECT`, searches across all projects assigned to the current user
- If the active context already defines a default Jira project, pass it explicitly as `PROJECT`
- Uses JQL: `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`
  or `project = <PROJECT> AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`
- Returns a compact TSV list ready to render as a table
- No preflight steps unless the command fails

### "Mis in progress"

Run exactly:

`scripts/jira-my-in-progress.sh [PROJECT]`

Behavior:
- Uses the explicit `PROJECT` argument when present
- Without `PROJECT`, searches across all projects assigned to the current user
- If the active context already defines a default Jira project, pass it explicitly as `PROJECT`
- Uses JQL: `assignee = currentUser() AND statusCategory = "In Progress" ORDER BY updated DESC`
  or `project = <PROJECT> AND assignee = currentUser() AND statusCategory = "In Progress" ORDER BY updated DESC`
- Returns a compact TSV list ready to render as a table
- No preflight steps unless the command fails

### "Issue <KEY>"

Run exactly:

`scripts/jira-issue.sh <KEY>`

Behavior:
- Fetches one issue by key
- Returns compact key-value output for direct summarization
- No extra reads unless the request explicitly asks for comments, history, or transitions

### "Transitions de <KEY>"

Run exactly:

`scripts/jira-transitions.sh <KEY>`

Behavior:
- Fetches available transitions for the issue
- Returns `id`, transition name, and destination status as TSV
- Use this only when the user explicitly asks for transitions or when debugging a workflow mismatch

### "Pasar <KEY> a <STATUS>"

Run exactly:

`scripts/jira-transition.sh <KEY> "<STATUS>" [--worklog 1h]`

Behavior:
- Fast-paths known transition ids for stable workflows such as `OPTICELL`
- Falls back to `GET /transitions` only when the cached id is missing or rejected
- Matches the target against transition name or destination status
- Use `--resolve-only` only when you need to inspect which id would be used without changing Jira
- For `Done`, include `--worklog`

### "Pasar <KEY> a Done"

Workflow:
- Require a worklog value before writing. If the user did not provide one, ask a short follow-up such as `Indicate the worklog to log for Done, or confirm 1h.`
- Send the transition with inline worklog, for example:

`scripts/jira-transition.sh <KEY> Done --worklog 1h`

Behavior:
- Do not read transitions first in the common case
- The script uses cached ids when available and falls back to live lookup automatically
- Do not send a plain `Done` transition first and "fix it later" with a separate worklog request
- Treat inline worklog on `Done` as the default company-safe path unless the user explicitly asks for a different Jira workflow

### "Comentar <KEY>"

Run exactly:

`scripts/jira-comment.sh <KEY> --text <TEXT>`

Behavior:
- Uses Jira API v2 plain-text comments to avoid manual ADF payload assembly
- Supports `--file <PATH>` or stdin when the comment body is multiline
- Prefer this wrapper over raw `jira-api.sh POST .../comment` in the common case

### Browser links

Use:

`scripts/jira-browse-url.sh --base`

or:

`scripts/jira-browse-url.sh <KEY> [COMMENT_ID]`

Behavior:
- `--base` returns the Jira browser base URL derived from `JIRA_URL`
- `<KEY>` returns the browser URL for that issue
- `<KEY> <COMMENT_ID>` returns a focused comment URL for that issue
- Use `--base` once when formatting a list of many issue links

### Generic JQL search

Run:

`scripts/jira-api.sh POST /rest/api/3/search/jql '{"jql":"...","maxResults":50,"fields":["summary","status","issuetype","priority","assignee","updated"]}'`

Then shape with `jq` into a compact table or bullet list.

### Resolve Jira user

Run:

`scripts/jira-resolve-user.sh <QUERY>`

Behavior:
- Resolves a Jira user from display name, email, or accountId
- Uses a local cache first and falls back to Jira live search only when needed
- Supports partial multi-word name matching, so queries like `Lautaro Farías` can match a full display name with middle names
- Updates the cache after an unambiguous live match

### Resolve Jira component

Run:

`scripts/jira-resolve-component.sh --project <KEY> <COMPONENT_NAME_OR_ID>`

Behavior:
- Resolves a component by name or id within a project
- Uses a per-project component cache and refreshes live only on miss/stale cache

### Resolve Jira field

Run:

`scripts/jira-resolve-field.sh <FIELD_NAME_OR_ID>`

Behavior:
- Resolves field ids such as Sprint without re-reading `/field` every turn
- Uses a local cache and refreshes live on miss

### Resolve sprint

Run one of:

`scripts/jira-resolve-sprint.sh --from-issue <ISSUE_KEY>`

`scripts/jira-resolve-sprint.sh --board <BOARD_ID> --state active [--name <SPRINT_NAME>]`

`scripts/jira-resolve-project-sprint.sh --project <KEY> --state active --name <SPRINT_NAME>`

Behavior:
- Reuses the sprint from an existing issue cheaply when that is the desired target
- Supports board-scoped live lookup with a short local cache
- Supports project-scoped lookup across project boards when the user gives only a project and sprint name
- Matches sprint-number aliases such as `Sprint 24` against sprint names like `Sp24 - Buscador`

### Create issue

Run:

`scripts/jira-create-issue.sh --project <KEY> --type <ISSUE_TYPE> --summary <TEXT> [--assignee <QUERY>] [--component <NAME>] [--sprint-project <KEY> --sprint-name <SPRINT_NAME>] [--sprint-from <ISSUE_KEY>] [--description <TEXT>]`

Behavior:
- Resolves assignee, components, sprint field id, and sprint id as needed
- Prefer `--sprint-project <KEY> --sprint-name <SPRINT_NAME>` when the user says “add it to sprint N” without naming a board
- Avoids manual payload assembly in common create flows
- Supports `--dry-run` to inspect the final payload before writing

### Create bug from issue

Run:

`scripts/jira-create-bug-from-issue.sh <SOURCE_ISSUE_KEY> --summary <TEXT> [--assignee <QUERY>] [--description <TEXT>]`

Behavior:
- Creates a Bug in the same project and sprint as the source issue
- Reuses the source issue to avoid separate sprint discovery steps
- Supports `--dry-run`

## Common API Patterns

- Current user or auth check:
  `jira-api.sh GET /rest/api/3/myself`
- JQL search:
  `jira-api.sh POST /rest/api/3/search/jql '{"jql":"..."}'`
- Issue details:
  `jira-api.sh GET /rest/api/3/issue/{issueIdOrKey}`
- Comments:
  `jira-api.sh GET /rest/api/3/issue/{issueIdOrKey}/comment`
  or
  `jira-comment.sh {issueIdOrKey} --text "Comentario"`
- Transitions:
  `jira-api.sh GET /rest/api/3/issue/{issueIdOrKey}/transitions`
  or
  `jira-transition.sh {issueIdOrKey} "{status}" [--worklog 1h]`
- Agile boards and sprints:
  use Jira Agile REST endpoints when the task is board- or sprint-specific, and confirm shapes in the official docs before writing

## Response Rules

- Prefer bullets or compact tables over prose dumps when listing issues.
- Include issue key, summary, status, priority, assignee, and updated date when they matter.
- Render issue keys as Markdown links when presenting them to the user, for example `[OPTICELL-112](https://your-site.atlassian.net/browse/OPTICELL-112)`.
- When referring to a specific comment and the issue key is known, render a direct comment link, for example `[comment 12345](https://your-site.atlassian.net/browse/OPTICELL-112?focusedCommentId=12345)`.
- Do not make extra Jira API calls just to build browser links. Use `jira-browse-url.sh` or derive them from a single `--base` lookup.
- For writes, report exactly what changed and on which issue.
- If a request is ambiguous and could change Jira state, clarify intent before writing.
