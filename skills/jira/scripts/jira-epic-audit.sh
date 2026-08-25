#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: jira-epic-audit.sh <EPIC_KEY>" >&2
  exit 1
fi

script_dir="${0:A:h}"
epic_key="$1"
payload="$(jq -cn --arg jql "parent = ${epic_key} ORDER BY key ASC" '{jql:$jql,maxResults:100,fields:["summary","status","assignee","labels","components","issuelinks"]}')"
response="$("$script_dir/jira-api.sh" POST /rest/api/3/search/jql "$payload")"

if [[ "$(jq -r '.isLast // true' <<<"$response")" != "true" ]]; then
  echo "More than 100 child issues were returned; pagination is required." >&2
  exit 1
fi

jq -r --arg epic_key "$epic_key" '
  def issue_row:
    "| \(.key) | \(.fields.summary | gsub("\\|"; "\\\\|")) | \(.fields.status.name) | \(.fields.assignee.displayName // "Unassigned") | \(((.fields.components // []) | map(.name) | join(", ")) // "—") | \(((.fields.labels // []) | join(", ")) // "—") |";
  def issue_links($source):
    [.fields.issuelinks[]? |
      if .outwardIssue then "| \($source) | \(.type.outward) | \(.outwardIssue.key) |"
      elif .inwardIssue then "| \(.inwardIssue.key) | \(.type.outward) | \($source) |"
      else empty end
    ];
  "# Audit: \($epic_key)\n\n" +
  "Child issues: \(.issues | length)\n\n" +
  "## Ownership and classification\n\n" +
  "| Key | Summary | Status | Assignee | Components | Labels |\n| --- | --- | --- | --- | --- | --- |\n" +
  ([.issues[] | issue_row] | join("\n")) + "\n\n" +
  "## Unassigned\n\n" +
  ([.issues[] | select(.fields.assignee == null) | "- \(.key): \(.fields.summary)"] | if length == 0 then "- Ninguno" else join("\n") end) + "\n\n" +
  "## Without components or labels\n\n" +
  ([.issues[] | select(((.fields.components // []) | length) == 0 and ((.fields.labels // []) | length) == 0) | "- \(.key): \(.fields.summary)"] | if length == 0 then "- Ninguno" else join("\n") end) + "\n\n" +
  "## Linked dependencies\n\n" +
  "| Blocker / source | Relationship | Blocked / target |\n| --- | --- | --- |\n" +
  ([.issues[] | issue_links(.key)[]] | unique | if length == 0 then "| — | — | — |" else join("\n") end)
' <<<"$response"
