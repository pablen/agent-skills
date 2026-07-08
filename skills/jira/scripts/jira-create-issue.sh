#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jira-create-issue.sh --project <KEY> --type <ISSUE_TYPE> --summary <TEXT> [options]

Options:
  --assignee <USER_QUERY>
  --priority <NAME>          (e.g. Highest, High, Medium, Low, Lowest)
  --component <NAME>         (repeatable)
  --sprint-id <ID>
  --sprint-from <ISSUE_KEY>
  --sprint-project <PROJECT_KEY> --sprint-name <SPRINT_NAME> [--sprint-state <STATE>]
  --sprint-board <BOARD_ID> --sprint-name <SPRINT_NAME> [--sprint-state <STATE>]
  --description <TEXT>
  --description-file <PATH>
  --description-adf-file <PATH>
  --dry-run
EOF
}

script_dir="${0:A:h}"

project=""
issue_type=""
summary=""
assignee_query=""
priority_name=""
components=()
sprint_id=""
sprint_from=""
sprint_project=""
sprint_board=""
sprint_name=""
sprint_state=""
description_text=""
description_file=""
description_adf_file=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project="${2:-}"
      shift 2
      ;;
    --type)
      issue_type="${2:-}"
      shift 2
      ;;
    --summary)
      summary="${2:-}"
      shift 2
      ;;
    --assignee)
      assignee_query="${2:-}"
      shift 2
      ;;
    --priority)
      priority_name="${2:-}"
      shift 2
      ;;
    --component)
      components+=("${2:-}")
      shift 2
      ;;
    --sprint-id)
      sprint_id="${2:-}"
      shift 2
      ;;
    --sprint-from)
      sprint_from="${2:-}"
      shift 2
      ;;
    --sprint-project)
      sprint_project="${2:-}"
      shift 2
      ;;
    --sprint-board)
      sprint_board="${2:-}"
      shift 2
      ;;
    --sprint-name)
      sprint_name="${2:-}"
      shift 2
      ;;
    --sprint-state)
      sprint_state="${2:-}"
      shift 2
      ;;
    --description)
      description_text="${2:-}"
      shift 2
      ;;
    --description-file)
      description_file="${2:-}"
      shift 2
      ;;
    --description-adf-file)
      description_adf_file="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$project" || -z "$issue_type" || -z "$summary" ]]; then
  usage
  exit 1
fi

if [[ -n "$description_file" && -n "$description_adf_file" ]]; then
  echo "Use only one of --description-file or --description-adf-file." >&2
  exit 1
fi

assignee_id=""
if [[ -n "$assignee_query" ]]; then
  assignee_id="$("$script_dir/jira-resolve-user.sh" "$assignee_query" | /usr/bin/awk -F'\t' 'NR==1{print $1}')"
fi

if [[ -z "$sprint_id" && -n "$sprint_from" ]]; then
  sprint_id="$("$script_dir/jira-resolve-sprint.sh" --from-issue "$sprint_from" | /usr/bin/awk -F'\t' 'NR==1{print $1}')"
fi

if [[ -z "$sprint_id" && -n "$sprint_project" ]]; then
  sprint_args=(--project "$sprint_project")
  if [[ -n "$sprint_state" ]]; then
    sprint_args+=(--state "$sprint_state")
  fi
  if [[ -n "$sprint_name" ]]; then
    sprint_args+=(--name "$sprint_name")
  fi
  sprint_id="$("$script_dir/jira-resolve-project-sprint.sh" "${sprint_args[@]}" | /usr/bin/awk -F'\t' 'NR==1{print $1}')"
fi

if [[ -z "$sprint_id" && -n "$sprint_board" ]]; then
  sprint_args=(--board "$sprint_board")
  if [[ -n "$sprint_state" ]]; then
    sprint_args+=(--state "$sprint_state")
  fi
  if [[ -n "$sprint_name" ]]; then
    sprint_args+=(--name "$sprint_name")
  fi
  sprint_id="$("$script_dir/jira-resolve-sprint.sh" "${sprint_args[@]}" | /usr/bin/awk -F'\t' 'NR==1{print $1}')"
fi

sprint_field_id=""
if [[ -n "$sprint_id" ]]; then
  sprint_field_id="$("$script_dir/jira-resolve-field.sh" sprint | /usr/bin/awk -F'\t' 'NR==1{print $1}')"
fi

description_json='null'
if [[ -n "$description_adf_file" ]]; then
  description_json="$(/bin/cat "$description_adf_file")"
elif [[ -n "$description_file" ]]; then
  description_text="$(/bin/cat "$description_file")"
fi

if [[ "$description_json" == 'null' && -n "$description_text" ]]; then
  description_json="$(
    jq -Rn --arg text "$description_text" '
      {
        type: "doc",
        version: 1,
        content: (
          ($text | split("\n\n"))
          | map({
              type: "paragraph",
              content: (
                if . == "" then []
                else [{type:"text", text:.}]
                end
              )
            })
        )
      }
    '
  )"
fi

components_json='[]'
if [[ ${#components[@]} -gt 0 ]]; then
  resolved_components=()
  for component in "${components[@]}"; do
    resolved_name="$("$script_dir/jira-resolve-component.sh" --project "$project" "$component" | /usr/bin/awk -F'\t' 'NR==1{print $2}')"
    resolved_components+=("$resolved_name")
  done
  components_json="$(printf '%s\n' "${resolved_components[@]}" | jq -R . | jq -s 'map({name: .})')"
fi

payload="$(
  jq -n \
    --arg project "$project" \
    --arg issueType "$issue_type" \
    --arg summary "$summary" \
    --arg priorityName "$priority_name" \
    --arg assigneeId "$assignee_id" \
    --arg sprintFieldId "$sprint_field_id" \
    --argjson sprintId "${sprint_id:-null}" \
    --argjson components "$components_json" \
    --argjson description "$description_json" '
      {
        fields: {
          project: {key: $project},
          summary: $summary,
          issuetype: {name: $issueType}
        }
      }
      | if ($priorityName | length) > 0 then .fields.priority = {name: $priorityName} else . end
      | if ($components | length) > 0 then .fields.components = $components else . end
      | if ($assigneeId | length) > 0 then .fields.assignee = {accountId: $assigneeId} else . end
      | if $description != null then .fields.description = $description else . end
      | if ($sprintFieldId | length) > 0 and $sprintId != null then
          .fields += {($sprintFieldId): $sprintId}
        else
          .
        end
    '
)"

if (( dry_run )); then
  print -r -- "$payload" | jq .
  exit 0
fi

result="$("$script_dir/jira-api.sh" POST /rest/api/3/issue "$payload")"
base_url="$("$script_dir/jira-browse-url.sh" --base)"

print -r -- "$result" | jq -r --arg base "$base_url" '
  [
    ["Key", .key],
    ["Id", .id],
    ["URL", ($base + "/browse/" + .key)]
  ] | .[] | @tsv
'
