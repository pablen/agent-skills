#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jira-update-issue.sh <ISSUE_KEY> --description-markdown <TEXT>
  jira-update-issue.sh <ISSUE_KEY> --description-markdown-file <PATH>
  jira-update-issue.sh <ISSUE_KEY> --assignee <USER_QUERY|me>
  jira-update-issue.sh <ISSUE_KEY> --parent <ISSUE_KEY>
  jira-update-issue.sh <ISSUE_KEY> --add-label <LABEL>

Options can be combined. --add-label preserves existing labels.
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

script_dir="${0:A:h}"
issue_key="$1"
shift
description_markdown=""
description_markdown_file=""
assignee_query=""
parent_key=""
add_label=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --description-markdown)
      description_markdown="${2:-}"
      shift 2
      ;;
    --description-markdown-file)
      description_markdown_file="${2:-}"
      shift 2
      ;;
    --assignee)
      assignee_query="${2:-}"
      shift 2
      ;;
    --parent)
      parent_key="${2:-}"
      shift 2
      ;;
    --add-label)
      add_label="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$description_markdown" && -n "$description_markdown_file" ]]; then
  echo "Use only one Markdown description option." >&2
  exit 1
fi

if [[ -n "$description_markdown_file" && ! -f "$description_markdown_file" ]]; then
  echo "File not found: $description_markdown_file" >&2
  exit 1
fi

if [[ -z "$description_markdown" && -z "$description_markdown_file" && -z "$assignee_query" && -z "$parent_key" && -z "$add_label" ]]; then
  usage
  exit 1
fi

description_json='null'
if [[ -n "$description_markdown" ]]; then
  description_json="$("$script_dir/jira-markdown-to-adf.sh" --text "$description_markdown")"
elif [[ -n "$description_markdown_file" ]]; then
  description_json="$("$script_dir/jira-markdown-to-adf.sh" --file "$description_markdown_file")"
fi

assignee_id=""
if [[ -n "$assignee_query" ]]; then
  assignee_id="$("$script_dir/jira-resolve-user.sh" "$assignee_query" | /usr/bin/awk -F'\t' 'NR == 1 {print $1}')"
fi

labels_json='null'
if [[ -n "$add_label" ]]; then
  existing_labels="$("$script_dir/jira-api.sh" GET "/rest/api/3/issue/${issue_key}?fields=labels" | jq '.fields.labels // []')"
  labels_json="$(jq -cn --argjson labels "$existing_labels" --arg label "$add_label" '$labels + [$label] | unique')"
fi

payload="$(jq -n \
  --arg assigneeId "$assignee_id" \
  --arg parentKey "$parent_key" \
  --argjson description "$description_json" \
  --argjson labels "$labels_json" '
    {fields: {}}
    | if $description != null then .fields.description = $description else . end
    | if ($assigneeId | length) > 0 then .fields.assignee = {accountId: $assigneeId} else . end
    | if ($parentKey | length) > 0 then .fields.parent = {key: $parentKey} else . end
    | if $labels != null then .fields.labels = $labels else . end
  ')"

"$script_dir/jira-api.sh" PUT "/rest/api/3/issue/${issue_key}" "$payload"
printf '%s\tupdated\n' "$issue_key"
