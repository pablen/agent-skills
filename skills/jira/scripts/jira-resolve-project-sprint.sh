#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: jira-resolve-project-sprint.sh --project <KEY> --name <SPRINT_NAME> [--state <active|future|closed|active,future>] [--refresh]
EOF
}

script_dir="${0:A:h}"
source "$script_dir/jira-cache-lib.sh"

project=""
name=""
state="active"
refresh=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project="${2:-}"
      shift 2
      ;;
    --name)
      name="${2:-}"
      shift 2
      ;;
    --state)
      state="${2:-}"
      shift 2
      ;;
    --refresh)
      refresh=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$project" || -z "$name" ]]; then
  usage
  exit 1
fi

project_normalized="$(normalize "$project")"
boards_cache_key="boards-${project_normalized}.json"
boards_ttl=86400

if (( refresh == 0 )) && cache_is_fresh "$boards_cache_key" "$boards_ttl"; then
  boards_json="$(cache_read "$boards_cache_key" 2>/dev/null || print '[]')"
else
  project_encoded="$(jq -rn --arg value "$project" '$value | @uri')"
  boards_response="$("$script_dir/jira-api.sh" GET "/rest/agile/1.0/board?projectKeyOrId=${project_encoded}")"
  boards_json="$(print -r -- "$boards_response" | jq '[.values[] | {id, name, type}]')"
  print -r -- "$boards_json" | cache_write "$boards_cache_key"
fi

matches=()
typeset -A seen_sprint_ids
while IFS=$'\t' read -r board_id _board_name _board_type; do
  [[ -z "$board_id" ]] && continue

  if result="$("$script_dir/jira-resolve-sprint.sh" --board "$board_id" --state "$state" --name "$name" 2>/dev/null)"; then
    sprint_id="$(print -r -- "$result" | /usr/bin/awk -F'\t' 'NR==1{print $1}')"
    if [[ -n "$sprint_id" && -z "${seen_sprint_ids[$sprint_id]:-}" ]]; then
      seen_sprint_ids[$sprint_id]=1
      matches+=("$result")
    fi
  fi
done < <(print -r -- "$boards_json" | jq -r '.[] | [(.id | tostring), (.name // ""), (.type // "")] | @tsv')

if [[ ${#matches[@]} -eq 1 ]]; then
  print -r -- "${matches[1]}"
  exit 0
fi

if [[ ${#matches[@]} -gt 1 ]]; then
  print -u2 -- "Ambiguous sprint ${name} for project ${project}:"
  printf '%s\n' "${matches[@]}" >&2
  exit 1
fi

print -u2 -- "Could not resolve sprint ${name} for project ${project}."
print -u2 -- "Boards checked:"
print -r -- "$boards_json" | jq -r '.[] | [(.id | tostring), (.name // ""), (.type // "")] | @tsv' >&2
exit 1
