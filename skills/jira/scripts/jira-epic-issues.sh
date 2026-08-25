#!/bin/zsh

set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: jira-epic-issues.sh <EPIC_KEY> [--description] [--links]" >&2
  exit 1
fi

script_dir="${0:A:h}"
epic_key="$1"
show_description=0
show_links=0

shift
for option in "$@"; do
  case "$option" in
    --description) show_description=1 ;;
    --links) show_links=1 ;;
    *) echo "Unknown option: $option" >&2; exit 1 ;;
  esac
done

fields='["summary","status","issuetype","priority","assignee","updated","labels","components","issuelinks"]'
if (( show_description )); then
  fields='["summary","status","issuetype","priority","assignee","updated","labels","components","issuelinks","description"]'
fi

payload="$(jq -cn --arg jql "parent = ${epic_key} ORDER BY key ASC" --argjson fields "$fields" '{jql:$jql,maxResults:100,fields:$fields}')"
response="$("$script_dir/jira-api.sh" POST /rest/api/3/search/jql "$payload")"

if [[ "$(jq -r '.isLast // true' <<<"$response")" != "true" ]]; then
  echo "More than 100 child issues were returned; pagination is required." >&2
  exit 1
fi

if (( ! show_description && ! show_links )); then
  jq -r '.issues[] | [
    .key, .fields.summary, .fields.issuetype.name, .fields.status.name,
    (.fields.priority.name // "Sin prioridad"), (.fields.assignee.displayName // "Unassigned"),
    .fields.updated, ((.fields.labels // []) | join(", ")),
    ((.fields.components // [] | map(.name)) | join(", "))
  ] | @tsv' <<<"$response"
  exit 0
fi

jq -r --argjson show_description "$show_description" --argjson show_links "$show_links" '
  def inline: [.content[]? | if .type == "text" then .text elif .type == "hardBreak" then "\n" else inline end] | join("");
  def render:
    if .type == "doc" then [.content[]? | render] | join("\n")
    elif .type == "heading" then ("## " + inline)
    elif .type == "paragraph" then inline
    elif .type == "bulletList" then [.content[]? | "- " + ([.content[]? | render] | join("\n"))] | join("\n")
    elif .type == "orderedList" then [.content[]? | "1. " + ([.content[]? | render] | join("\n"))] | join("\n")
    elif .type == "listItem" then [.content[]? | render] | join("\n")
    else inline
    end;
  def issue_links($source):
    [.fields.issuelinks[]? |
      if .outwardIssue then "- \(.type.name): \($source) \(.type.outward) \(.outwardIssue.key)"
      elif .inwardIssue then "- \(.type.name): \(.inwardIssue.key) \(.type.outward) \($source)"
      else empty end
    ] | if length == 0 then "- Ninguno" else join("\n") end;
  .issues[] |
  "# \(.key) — \(.fields.summary)\n" +
  "Estado: \(.fields.status.name) · Asignado: \(.fields.assignee.displayName // "Unassigned") · Componentes: \(((.fields.components // []) | map(.name) | join(", ") | if . == "" then "—" else . end)) · Labels: \(((.fields.labels // []) | join(", ") | if . == "" then "—" else . end))\n" +
  (if $show_description == 1 then "\nDescripción:\n" + (if .fields.description then (.fields.description | render) else "(sin descripción)" end) + "\n" else "" end) +
  (if $show_links == 1 then "\nRelaciones:\n" + issue_links(.key) + "\n" else "" end)
' <<<"$response"
