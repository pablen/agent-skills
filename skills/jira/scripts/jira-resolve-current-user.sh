#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: jira-resolve-current-user.sh [--refresh]
EOF
}

script_dir="${0:A:h}"
source "$script_dir/jira-cache-lib.sh"

refresh=0
if [[ ${1:-} == "--refresh" ]]; then
  refresh=1
  shift
fi

if [[ $# -ne 0 ]]; then
  usage
  exit 1
fi

cache_key="current-user.json"

if (( refresh == 0 )); then
  if cached_json="$(cache_read "$cache_key" 2>/dev/null)"; then
    print -r -- "$cached_json" | jq -r '[.accountId, .displayName, (.emailAddress // ""), "cache"] | @tsv'
    exit 0
  fi
fi

live_json="$("$script_dir/jira-api.sh" GET /rest/api/3/myself)"
current_user="$(print -r -- "$live_json" | jq '{accountId, displayName, emailAddress}')"
print -r -- "$current_user" | cache_write "$cache_key"
print -r -- "$current_user" | jq -r '[.accountId, .displayName, (.emailAddress // ""), "live"] | @tsv'
