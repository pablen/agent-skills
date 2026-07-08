#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: jira-resolve-component.sh --project <KEY> <COMPONENT_NAME_OR_ID> [--refresh]
EOF
}

script_dir="${0:A:h}"
source "$script_dir/jira-cache-lib.sh"

project=""
query=""
refresh=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project="${2:-}"
      shift 2
      ;;
    --refresh)
      refresh=1
      shift
      ;;
    *)
      if [[ -n "$query" ]]; then
        echo "Only one component query is supported." >&2
        usage
        exit 1
      fi
      query="$1"
      shift
      ;;
  esac
done

if [[ -z "$project" || -z "$query" ]]; then
  usage
  exit 1
fi

project_normalized="$(normalize "$project")"
query_normalized="$(normalize "$query")"
cache_key="components-${project_normalized}.json"
ttl=86400

find_in_components_json() {
  jq -r --arg q "$query" --arg qn "$query_normalized" '
    def norm: ascii_downcase | gsub("^[[:space:]]+|[[:space:]]+$"; "") | gsub("[[:space:]]+"; " ");
    [
      .[]
      | select((.id // "") == $q or ((.name // "" | norm) == $qn))
    ] as $exact
    | if ($exact | length) == 1 then
        $exact[0]
      else
        [
          .[]
          | select((.id // "" | contains($q)) or (.name // "" | norm | contains($qn)))
        ] as $contains
        | if ($contains | length) == 1 then $contains[0] else empty end
      end
    | [(.id // ""), (.name // "")] | @tsv
  '
}

if (( refresh == 0 )) && cache_is_fresh "$cache_key" "$ttl"; then
  if cache_json="$(cache_read "$cache_key" 2>/dev/null)"; then
    if result="$(print -r -- "$cache_json" | find_in_components_json)" && [[ -n "$result" ]]; then
      printf '%s\t%s\n' "$result" "cache"
      exit 0
    fi
  fi
fi

project_encoded="$(jq -rn --arg value "$project" '$value | @uri')"
live_json="$("$script_dir/jira-api.sh" GET "/rest/api/3/project/${project_encoded}/components")"
values_json="$(print -r -- "$live_json" | jq '[.[] | {id, name}]')"
print -r -- "$values_json" | cache_write "$cache_key"

if result="$(print -r -- "$values_json" | find_in_components_json)" && [[ -n "$result" ]]; then
  printf '%s\t%s\n' "$result" "live"
  exit 0
fi

print -u2 -- "Could not resolve Jira component for project ${project}: ${query}"
print -u2 -- "Available components:"
print -r -- "$values_json" | jq -r '.[] | [(.id // ""), (.name // "")] | @tsv' >&2
exit 1
