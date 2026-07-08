#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: jira-issue-full.sh <ISSUE_KEY>" >&2
  exit 1
fi

script_dir="${0:A:h}"
issue_key="$1"

"$script_dir/jira-api.sh" GET "/rest/api/3/issue/${issue_key}?fields=summary,status,issuetype,priority,assignee,reporter,updated,description,labels,components" |
  jq -r '
    def adf_text:
      if type == "object" then
        if .type == "text" then (.text // "")
        elif .type == "hardBreak" then "\n"
        elif .content then (.content | map(adf_text) | join(""))
        else ""
        end
      elif type == "array" then map(adf_text) | join("\n")
      else ""
      end;

    def adf_blocks:
      if .content then
        [ .content[] | adf_text ] | map(select(length > 0)) | join("\n\n")
      else ""
      end;

    [
      ["Key",        .key],
      ["Summary",    .fields.summary],
      ["Type",       .fields.issuetype.name],
      ["Status",     .fields.status.name],
      ["Priority",   (.fields.priority.name // "Sin prioridad")],
      ["Assignee",   (.fields.assignee.displayName // "Unassigned")],
      ["Reporter",   (.fields.reporter.displayName // "Unknown")],
      ["Updated",    .fields.updated],
      ["Labels",     ((.fields.labels // []) | join(", ") | if . == "" then "—" else . end)],
      ["Components", ((.fields.components // [] | map(.name)) | join(", ") | if . == "" then "—" else . end)],
      ["Description", (if .fields.description then (.fields.description | adf_blocks) else "—" end)]
    ] | .[] | "\(.[0])\t\(.[1])"
  '
