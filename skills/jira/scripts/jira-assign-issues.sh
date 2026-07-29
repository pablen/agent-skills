#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: jira-assign-issues.sh --to <USER_QUERY|me> <ISSUE_KEY> [ISSUE_KEY...]
EOF
}

script_dir="${0:A:h}"
assignee_query=""
issue_keys=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      assignee_query="${2:-}"
      shift 2
      ;;
    *)
      issue_keys+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$assignee_query" || ${#issue_keys[@]} -eq 0 ]]; then
  usage
  exit 1
fi

resolve_assignee() {
  local refresh_flag="${1:-}"
  local args=("$assignee_query")
  if [[ "$refresh_flag" == "--refresh" ]]; then
    args+=("--refresh")
  fi

  assignee="$("$script_dir/jira-resolve-user.sh" "${args[@]}")"
  assignee_id="$(print -r -- "$assignee" | /usr/bin/awk -F'\t' 'NR == 1 {print $1}')"
  assignee_name="$(print -r -- "$assignee" | /usr/bin/awk -F'\t' 'NR == 1 {print $2}')"
  payload="$(jq -cn --arg accountId "$assignee_id" '{fields: {assignee: {accountId: $accountId}}}')"
}

resolve_assignee

for issue_key in "${issue_keys[@]}"; do
  if ! "$script_dir/jira-api.sh" PUT "/rest/api/3/issue/${issue_key}" "$payload"; then
    resolve_assignee --refresh
    "$script_dir/jira-api.sh" PUT "/rest/api/3/issue/${issue_key}" "$payload"
  fi
  printf '%s\t%s\n' "$issue_key" "$assignee_name"
done
