#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: jira-resolve-field.sh <FIELD_NAME_OR_ID> [--refresh]
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

script_dir="${0:A:h}"
source "$script_dir/jira-cache-lib.sh"

query=""
refresh=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh)
      refresh=1
      shift
      ;;
    *)
      if [[ -n "$query" ]]; then
        echo "Only one field query is supported." >&2
        usage
        exit 1
      fi
      query="$1"
      shift
      ;;
  esac
done

if [[ -z "$query" ]]; then
  usage
  exit 1
fi

case "$(normalize "$query")" in
  sprint|sprints)
    query="Sprint"
    ;;
esac

cache_key="fields.json"
query_normalized="$(normalize "$query")"

find_in_fields_json() {
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

if (( refresh == 0 )); then
  if cache_json="$(cache_read "$cache_key" 2>/dev/null)"; then
    if result="$(print -r -- "$cache_json" | find_in_fields_json)" && [[ -n "$result" ]]; then
      printf '%s\t%s\n' "$result" "cache"
      exit 0
    fi
  fi
fi

live_json="$("$script_dir/jira-api.sh" GET '/rest/api/3/field')"
print -r -- "$live_json" | cache_write "$cache_key"

if result="$(print -r -- "$live_json" | find_in_fields_json)" && [[ -n "$result" ]]; then
  printf '%s\t%s\n' "$result" "live"
  exit 0
fi

print -u2 -- "Could not resolve Jira field: ${query}"
exit 1
