#!/bin/zsh

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: jira-issue.sh <ISSUE_KEY> [--description]" >&2
  exit 1
fi

script_dir="${0:A:h}"
issue_key="$1"
show_description=0

if [[ $# -eq 2 ]]; then
  if [[ "$2" != "--description" ]]; then
    echo "Unknown option: $2" >&2
    exit 1
  fi
  show_description=1
fi

fields="summary,status,issuetype,priority,assignee,reporter,updated"
if (( show_description )); then
  fields+=",description"
fi

"$script_dir/jira-api.sh" GET "/rest/api/3/issue/${issue_key}?fields=${fields}" |
  jq -r --argjson show_description "$show_description" '
    def inline: [.content[]? | if .type == "text" then .text elif .type == "hardBreak" then "\n" else inline end] | join("");
    def render:
      if .type == "doc" then [.content[]? | render] | join("\n")
      elif .type == "heading" then ("## " + inline)
      elif .type == "paragraph" then inline
      elif .type == "bulletList" then [.content[]? | "- " + ([.content[]? | render] | join("\n"))] | join("\n")
      elif .type == "orderedList" then [.content[]? | "1. " + ([.content[]? | render] | join("\n"))] | join("\n")
      elif .type == "listItem" then [.content[]? | render] | join("\n")
      elif .type == "taskList" then [.content[]? | render] | join("\n")
      elif .type == "taskItem" then "- [" + (if .attrs.state == "DONE" then "x" else " " end) + "] " + inline
      else inline
      end;
    (
      [
        ["Key", .key],
        ["Summary", .fields.summary],
        ["Type", .fields.issuetype.name],
        ["Status", .fields.status.name],
        ["Priority", (.fields.priority.name // "Sin prioridad")],
        ["Assignee", (.fields.assignee.displayName // "Unassigned")],
        ["Reporter", (.fields.reporter.displayName // "Unknown")],
        ["Updated", .fields.updated]
      ] | .[] | @tsv
    ),
    (
      if $show_description == 1 then "\nDescripción:\n" + (.fields.description | if . == null then "(sin descripción)" else render end) else empty end
    )
  '
