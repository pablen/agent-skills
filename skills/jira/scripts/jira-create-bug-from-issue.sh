#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jira-create-bug-from-issue.sh <SOURCE_ISSUE_KEY> --summary <TEXT> [options]

Options:
  --assignee <USER_QUERY>
  --description <TEXT>
  --description-file <PATH>
  --description-adf-file <PATH>
  --dry-run
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

script_dir="${0:A:h}"
source_issue="$1"
shift

summary=""
assignee_query=""
description_text=""
description_file=""
description_adf_file=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary)
      summary="${2:-}"
      shift 2
      ;;
    --assignee)
      assignee_query="${2:-}"
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

if [[ -z "$summary" ]]; then
  usage
  exit 1
fi

source_json="$("$script_dir/jira-api.sh" GET "/rest/api/3/issue/${source_issue}?fields=project")"
project_key="$(print -r -- "$source_json" | jq -r '.fields.project.key')"

cmd=(
  "$script_dir/jira-create-issue.sh"
  --project "$project_key"
  --type Bug
  --summary "$summary"
  --sprint-from "$source_issue"
)

if [[ -n "$assignee_query" ]]; then
  cmd+=(--assignee "$assignee_query")
fi

if [[ -n "$description_text" ]]; then
  cmd+=(--description "$description_text")
fi

if [[ -n "$description_file" ]]; then
  cmd+=(--description-file "$description_file")
fi

if [[ -n "$description_adf_file" ]]; then
  cmd+=(--description-adf-file "$description_adf_file")
fi

if (( dry_run )); then
  cmd+=(--dry-run)
fi

"${cmd[@]}"
