#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jira-resolve-sprint.sh --from-issue <ISSUE_KEY>
  jira-resolve-sprint.sh --board <BOARD_ID> [--state <active|future|closed>] --name <SPRINT_NAME>
  jira-resolve-sprint.sh --board <BOARD_ID> --state <active|future|closed>

Options:
  --refresh   Bypass sprint cache and refresh from Jira
EOF
}

script_dir="${0:A:h}"
source "$script_dir/jira-cache-lib.sh"

from_issue=""
board_id=""
state=""
name=""
refresh=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-issue)
      from_issue="${2:-}"
      shift 2
      ;;
    --board)
      board_id="${2:-}"
      shift 2
      ;;
    --state)
      state="${2:-}"
      shift 2
      ;;
    --name)
      name="${2:-}"
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

if [[ -n "$from_issue" ]]; then
  sprint_field_id="$("$script_dir/jira-resolve-field.sh" sprint | /usr/bin/awk -F'\t' 'NR==1{print $1}')"
  issue_json="$("$script_dir/jira-api.sh" GET "/rest/api/3/issue/${from_issue}?fields=${sprint_field_id}")"
  result="$(
    print -r -- "$issue_json" |
      jq -r --arg field "$sprint_field_id" '
        .fields[$field] as $sprints
        | if ($sprints | type) == "array" and ($sprints | length) > 0 then
            $sprints[0]
          else
            empty
          end
        | [(.id // ""), (.name // ""), (.state // ""), ((.boardId // "") | tostring)] | @tsv
      '
  )"

  if [[ -z "$result" ]]; then
    print -u2 -- "Issue ${from_issue} has no sprint assigned."
    exit 1
  fi

  existing_json="$(cache_read "sprints.json" 2>/dev/null || print '[]')"
  sprint_json="$(
    print -r -- "$issue_json" |
      jq -c --arg field "$sprint_field_id" '.fields[$field][0]'
  )"
  updated_cache="$(
    jq -n --argjson existing "$existing_json" --argjson sprint "$sprint_json" '
      ($existing + [$sprint]) | unique_by(.id) | sort_by(.name // "", .id // "")
    '
  )"
  print -r -- "$updated_cache" | cache_write "sprints.json"

  printf '%s\t%s\n' "$result" "issue"
  exit 0
fi

if [[ -z "$board_id" ]]; then
  usage
  exit 1
fi

if [[ -z "$state" ]]; then
  state="active"
fi

cache_key="sprints-board-${board_id}-${state}.json"
ttl=21600
name_normalized="$(normalize "$name")"

find_in_sprints_json() {
  jq -r --arg name "$name" --arg nn "$name_normalized" '
    def norm: ascii_downcase | gsub("^[[:space:]]+|[[:space:]]+$"; "") | gsub("[[:space:]]+"; " ");
    def sprint_number:
      (try (norm | capture("(?<n>[0-9]+)").n) catch "");
    ($nn | sprint_number) as $requested_number
    |
    if ($name | length) == 0 then
      if length == 1 then .[0] else empty end
    else
      [
        .[]
        | select(((.name // "" | norm) == $nn))
      ] as $exact
      | if ($exact | length) == 1 then
          $exact[0]
        else
          [
            .[]
            | select(.name // "" | norm | contains($nn))
          ] as $contains
          | if ($contains | length) == 1 then
              $contains[0]
            else
              [
                .[]
                | select($requested_number != "" and ((.name // "" | sprint_number) == $requested_number))
              ] as $number_match
              | if ($number_match | length) == 1 then $number_match[0] else empty end
            end
        end
    end
    | [(.id // ""), (.name // ""), (.state // ""), ((.boardId // "") | tostring)] | @tsv
  '
}

if (( refresh == 0 )) && cache_is_fresh "$cache_key" "$ttl"; then
  if cache_json="$(cache_read "$cache_key" 2>/dev/null)"; then
    if result="$(print -r -- "$cache_json" | find_in_sprints_json)" && [[ -n "$result" ]]; then
      printf '%s\t%s\n' "$result" "cache"
      exit 0
    fi
  fi
fi

live_json="$("$script_dir/jira-api.sh" GET "/rest/agile/1.0/board/${board_id}/sprint?state=${state}&maxResults=50")"
values_json="$(print -r -- "$live_json" | jq '[.values[] | {id, name, state, boardId}]')"
print -r -- "$values_json" | cache_write "$cache_key"

if result="$(print -r -- "$values_json" | find_in_sprints_json)" && [[ -n "$result" ]]; then
  printf '%s\t%s\n' "$result" "live"
  exit 0
fi

print -u2 -- "Could not resolve sprint for board ${board_id}."
if [[ -n "$name" ]]; then
  print -u2 -- "Requested sprint name: ${name}"
fi
print -u2 -- "Available sprints:"
print -r -- "$values_json" | jq -r '.[] | [(.id // ""), (.name // ""), (.state // ""), ((.boardId // "") | tostring)] | @tsv' >&2
exit 1
