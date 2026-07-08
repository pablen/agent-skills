#!/bin/zsh

set -euo pipefail

CURL_BIN="/usr/bin/curl"
AWK_BIN="/usr/bin/awk"
CAT_BIN="/bin/cat"
RM_BIN="/bin/rm"

if [[ -f "$HOME/.jira-env" ]]; then
  source "$HOME/.jira-env"
fi

if [[ -z "${JIRA_URL:-}" || -z "${JIRA_EMAIL:-}" || -z "${JIRA_TOKEN:-}" ]]; then
  echo "Missing Jira credentials. Expected JIRA_URL, JIRA_EMAIL, and JIRA_TOKEN." >&2
  exit 1
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: jira-api.sh <GET|POST|PUT|DELETE> <path> [json-body]" >&2
  exit 1
fi

method="$1"
path="$2"
body="${3:-}"

case "$method" in
  GET|POST|PUT|DELETE) ;;
  *)
    echo "Unsupported method: $method" >&2
    exit 1
    ;;
esac

if [[ "$path" != /rest/* ]]; then
  echo "Path must start with /rest/" >&2
  exit 1
fi

tmp_dir="$(/usr/bin/mktemp -d 2>/dev/null || mktemp -d)"
trap '"$RM_BIN" -rf "$tmp_dir"' EXIT

headers_file="$tmp_dir/headers"
body_file="$tmp_dir/body"

curl_args=(
  -L
  -sS
  -u "$JIRA_EMAIL:$JIRA_TOKEN"
  -H "Accept: application/json"
  -X "$method"
  -D "$headers_file"
  -o "$body_file"
)

if [[ -n "$body" ]]; then
  curl_args+=(
    -H "Content-Type: application/json"
    --data "$body"
  )
fi

"$CURL_BIN" "${curl_args[@]}" "${JIRA_URL}${path}"

status_code="$(
  "$AWK_BIN" 'toupper($1) ~ /^HTTP/ { code=$2 } END { print code }' "$headers_file"
)"

if [[ -z "$status_code" ]]; then
  echo "Could not determine Jira response status." >&2
  exit 1
fi

if (( status_code >= 400 )); then
  if [[ -s "$body_file" ]]; then
    "$CAT_BIN" "$body_file" >&2
  else
    echo "Jira request failed with HTTP $status_code." >&2
  fi
  exit 1
fi

if [[ -s "$body_file" ]]; then
  "$CAT_BIN" "$body_file"
fi
