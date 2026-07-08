#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: jira-transition.sh <ISSUE_KEY> <TARGET_STATUS> [--worklog <DURATION>] [--resolve-only]
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

script_dir="${0:A:h}"
issue_key="$1"
shift
target_status="$1"
shift
worklog=""
resolve_only=0
last_error=""
live_transitions_json=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worklog)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --worklog" >&2
        exit 1
      fi
      worklog="$2"
      shift 2
      ;;
    --resolve-only)
      resolve_only=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

normalize() {
  print -r -- "$1" | /usr/bin/awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); gsub(/[[:space:]]+/, " ", $0); print tolower($0) }'
}

target_normalized="$(normalize "$target_status")"
project_key="${issue_key%%-*}"

if [[ "$target_normalized" == "done" && $resolve_only -eq 0 && -z "$worklog" ]]; then
  echo "Done transitions require --worklog <DURATION>." >&2
  exit 1
fi

typeset -A known_transition_ids=(
  ["OPTICELL:to do"]="11"
  ["OPTICELL:in progress"]="21"
  ["OPTICELL:done"]="31"
  ["OPTICELL:pending"]="51"
  ["OPTICELL:cancelado"]="61"
  ["OPTICELL:cancelled"]="61"
)

build_payload() {
  local transition_id="$1"

  if [[ "$target_normalized" == "done" ]]; then
    jq -cn --arg id "$transition_id" --arg timeSpent "$worklog" '{transition:{id:$id},update:{worklog:[{add:{timeSpent:$timeSpent}}]}}'
    return
  fi

  jq -cn --arg id "$transition_id" '{transition:{id:$id}}'
}

post_transition() {
  local transition_id="$1"
  local payload
  payload="$(build_payload "$transition_id")"

  local output
  if output="$("$script_dir/jira-api.sh" POST "/rest/api/3/issue/${issue_key}/transitions" "$payload" 2>&1)"; then
    if [[ -n "$output" ]]; then
      print -r -- "$output"
    fi
    return 0
  fi

  last_error="$output"
  return 1
}

resolve_live_transition_id() {
  live_transitions_json="$("$script_dir/jira-api.sh" GET "/rest/api/3/issue/${issue_key}/transitions")"

  print -r -- "$live_transitions_json" | jq -r --arg target "$target_normalized" '
    def norm: ascii_downcase | gsub("^[[:space:]]+|[[:space:]]+$"; "") | gsub("[[:space:]]+"; " ");
    .transitions
    | map(select(((.name // "") | norm) == $target or ((.to.name // "") | norm) == $target))
    | .[0].id // empty
  '
}

print_available_transitions() {
  if [[ -z "$live_transitions_json" ]]; then
    return
  fi

  print -u2 -- "Available transitions:"
  print -r -- "$live_transitions_json" | jq -r '.transitions[] | "- \(.id)\t\(.name)\t\(.to.name // "")"' >&2
}

cached_key="${project_key}:${target_normalized}"
cached_id="${known_transition_ids[$cached_key]-}"

if [[ -n "$cached_id" ]]; then
  if (( resolve_only )); then
    print -r -- "${cached_id}	cache"
    exit 0
  fi

  if post_transition "$cached_id"; then
    exit 0
  fi
fi

live_id="$(resolve_live_transition_id)"

if [[ -z "$live_id" ]]; then
  if [[ -n "$last_error" ]]; then
    print -u2 -- "$last_error"
  fi
  print -u2 -- "Could not resolve a transition to '${target_status}' for ${issue_key}."
  print_available_transitions
  exit 1
fi

if (( resolve_only )); then
  print -r -- "${live_id}	live"
  exit 0
fi

if [[ -n "$cached_id" && "$live_id" == "$cached_id" && -n "$last_error" ]]; then
  print -u2 -- "$last_error"
  exit 1
fi

if post_transition "$live_id"; then
  exit 0
fi

print -u2 -- "$last_error"
exit 1
