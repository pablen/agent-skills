#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: jira-resolve-user.sh <QUERY> [--refresh]
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
        echo "Only one query argument is supported." >&2
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

cache_key="users.json"
query_normalized="$(normalize "$query")"

find_in_users_json() {
  jq -r --arg q "$query" --arg qn "$query_normalized" '
    def norm: ascii_downcase | gsub("^[[:space:]]+|[[:space:]]+$"; "") | gsub("[[:space:]]+"; " ");
    def words($s): ($s | norm | split(" ") | map(select(length > 0)));
    def has_all_words($haystack; $needle):
      (words($needle)) as $needle_words
      | ($haystack | norm) as $normalized_haystack
      | (($needle_words | length) > 0 and all($needle_words[]; . as $word | $normalized_haystack | contains($word)));
    [
      .[]
      | select(
          (.accountId // "") == $q
          or ((.emailAddress // "" | ascii_downcase) == ($q | ascii_downcase))
          or ((.displayName // "" | norm) == $qn)
        )
    ] as $exact
    | if ($exact | length) == 1 then
        $exact[0]
      else
          [
            .[]
            | select(
                (.accountId // "" | contains($q))
                or (.emailAddress // "" | ascii_downcase | contains($q | ascii_downcase))
                or (.displayName // "" | norm | contains($qn))
                or has_all_words((.displayName // ""); $qn)
                or has_all_words((.emailAddress // ""); $qn)
              )
          ] as $contains
          | if ($contains | length) == 1 then $contains[0] else empty end
      end
    | [(.accountId // ""), (.displayName // ""), (.emailAddress // "")] | @tsv
  '
}

print_ambiguous_results() {
  local json="$1"
  print -u2 -- "Ambiguous Jira users for query: ${query}"
  print -r -- "$json" | jq -r '.[] | [(.accountId // ""), (.displayName // ""), (.emailAddress // "")] | @tsv' >&2
}

if (( refresh == 0 )); then
  if cache_json="$(cache_read "$cache_key" 2>/dev/null)"; then
    if result="$(print -r -- "$cache_json" | find_in_users_json)" && [[ -n "$result" ]]; then
      printf '%s\t%s\n' "$result" "cache"
      exit 0
    fi
  fi
fi

query_encoded="$(jq -rn --arg value "$query" '$value | @uri')"
live_json="$("$script_dir/jira-api.sh" GET "/rest/api/3/user/search?query=${query_encoded}&maxResults=20")"

filtered_json="$(print -r -- "$live_json" | jq '[.[] | select(.active == true)]')"

result="$(print -r -- "$filtered_json" | find_in_users_json || true)"

if [[ -z "$result" ]]; then
  count="$(print -r -- "$filtered_json" | jq 'length')"
  if [[ "$count" -gt 1 ]]; then
    print_ambiguous_results "$filtered_json"
  else
    print -u2 -- "No Jira user found for query: ${query}"
  fi
  exit 1
fi

existing_json="$(cache_read "$cache_key" 2>/dev/null || print '[]')"
updated_cache="$(
  jq -n --argjson existing "$existing_json" --argjson incoming "$filtered_json" '
    ($existing + $incoming)
    | unique_by(.accountId)
    | sort_by(.displayName // "", .emailAddress // "")
  '
)"
print -r -- "$updated_cache" | cache_write "$cache_key"

printf '%s\t%s\n' "$result" "live"
