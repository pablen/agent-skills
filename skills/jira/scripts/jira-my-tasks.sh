#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project="${1:-}"

if [[ -n "$project" ]]; then
  jql="project = ${project} AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
else
  jql="assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
fi

"$script_dir/jira-api.sh" POST /rest/api/3/search/jql "$(jq -cn --arg jql "$jql" '{jql:$jql,maxResults:50,fields:["summary","status","issuetype","priority","assignee","updated"]}')" |
  jq -r '.issues[] | [ .key, .fields.summary, .fields.status.name, (.fields.priority.name // "Sin prioridad"), (.fields.assignee.displayName // "Unassigned"), .fields.updated ] | @tsv'
