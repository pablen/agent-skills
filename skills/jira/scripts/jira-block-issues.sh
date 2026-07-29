#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jira-block-issues.sh --blocker <ISSUE_KEY> --blocked <ISSUE_KEY> [--replace-reverse]

Creates the semantic relationship: <blocker> blocks <blocked>.
Use --replace-reverse only to repair an existing relationship in the wrong direction.
EOF
}

script_dir="${0:A:h}"
blocker=""
blocked=""
replace_reverse=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --blocker)
      blocker="${2:-}"
      shift 2
      ;;
    --blocked)
      blocked="${2:-}"
      shift 2
      ;;
    --replace-reverse)
      replace_reverse=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$blocker" || -z "$blocked" || "$blocker" == "$blocked" ]]; then
  usage
  exit 1
fi

if (( replace_reverse )); then
  links_json="$("$script_dir/jira-api.sh" GET "/rest/api/3/issue/${blocked}?fields=issuelinks")"
  expected_id="$(print -r -- "$links_json" | jq -r --arg blocker "$blocker" '
    .fields.issuelinks[]?
    | select(.type.name == "Blocks" and .inwardIssue.key == $blocker)
    | .id
  ' | head -n 1)"

  if [[ -n "$expected_id" ]]; then
    printf '%s already blocks %s\n' "$blocker" "$blocked"
    exit 0
  fi

  reverse_ids=("${(@f)$(print -r -- "$links_json" | jq -r --arg blocker "$blocker" '
    .fields.issuelinks[]?
    | select(.type.name == "Blocks" and .outwardIssue.key == $blocker)
    | .id
  ')}")

  for link_id in "${reverse_ids[@]}"; do
    "$script_dir/jira-api.sh" DELETE "/rest/api/3/issueLink/${link_id}"
  done
fi

payload="$(jq -cn --arg blocker "$blocker" --arg blocked "$blocked" '
  {
    type: {name: "Blocks"},
    inwardIssue: {key: $blocker},
    outwardIssue: {key: $blocked}
  }
')"
"$script_dir/jira-api.sh" POST /rest/api/3/issueLink "$payload"
printf '%s blocks %s\n' "$blocker" "$blocked"
