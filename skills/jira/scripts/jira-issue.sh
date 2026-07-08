#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: jira-issue.sh <ISSUE_KEY>" >&2
  exit 1
fi

script_dir="${0:A:h}"
issue_key="$1"

"$script_dir/jira-api.sh" GET "/rest/api/3/issue/${issue_key}?fields=summary,status,issuetype,priority,assignee,reporter,updated" |
  jq -r '[
    ["Key", .key],
    ["Summary", .fields.summary],
    ["Type", .fields.issuetype.name],
    ["Status", .fields.status.name],
    ["Priority", (.fields.priority.name // "Sin prioridad")],
    ["Assignee", (.fields.assignee.displayName // "Unassigned")],
    ["Reporter", (.fields.reporter.displayName // "Unknown")],
    ["Updated", .fields.updated]
  ] | .[] | @tsv'
