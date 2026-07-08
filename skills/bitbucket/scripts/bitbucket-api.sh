#!/bin/zsh

set -euo pipefail

CURL_BIN="/usr/bin/curl"
AWK_BIN="/usr/bin/awk"
CAT_BIN="/bin/cat"
RM_BIN="/bin/rm"

# ── Credentials: repo-local first (.bitbucket-token), then global fallback (~/.bitbucket-env) ──
BITBUCKET_API_TOKEN="${BITBUCKET_API_TOKEN:-}"
if [[ -f "./.bitbucket-token" ]]; then
  source "./.bitbucket-token"
elif [[ -f "$HOME/.bitbucket-env" ]]; then
  source "$HOME/.bitbucket-env"
fi

if [[ -z "${BITBUCKET_API_TOKEN:-}" ]]; then
  echo "Missing Bitbucket credentials." >&2
  echo "" >&2
  echo "Create a Repository Access Token:" >&2
  echo "  1. Go to https://bitbucket.org/<WORKSPACE>/<REPO>/admin/access-tokens" >&2
  echo "  2. Create token with scopes: Repositories: Read, Pull requests: Read+Write, Pipelines: Read" >&2
  echo "  3. Save it in ./.bitbucket-token (repo-local, recommended) or ~/.bitbucket-env (global):" >&2
  echo "" >&2
  echo "     BITBUCKET_API_TOKEN=<your-token>" >&2
  echo "" >&2
  exit 1
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: bitbucket-api.sh <GET|POST|PUT|DELETE> <path> [json-body]" >&2
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

tmp_dir="$(/usr/bin/mktemp -d 2>/dev/null || mktemp -d)"
trap '"$RM_BIN" -rf "$tmp_dir"' EXIT

headers_file="$tmp_dir/headers"
body_file="$tmp_dir/body"

curl_args=(
  -L
  -sS
  -H "Authorization: Bearer $BITBUCKET_API_TOKEN"
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

"$CURL_BIN" "${curl_args[@]}" "https://api.bitbucket.org${path}"

status_code="$(
  "$AWK_BIN" 'toupper($1) ~ /^HTTP/ { code=$2 } END { print code }' "$headers_file"
)"

if [[ -z "$status_code" ]]; then
  echo "Could not determine Bitbucket response status." >&2
  exit 1
fi

if (( status_code >= 400 )); then
  if [[ -s "$body_file" ]]; then
    "$CAT_BIN" "$body_file" >&2
  else
    echo "Bitbucket request failed with HTTP $status_code." >&2
  fi
  if (( status_code == 401 )); then
    echo "" >&2
    echo "The token may be expired or lack the required scopes." >&2
    echo "Create a new one at: https://bitbucket.org/<WORKSPACE>/<REPO>/admin/access-tokens" >&2
    echo "Required scopes: Repositories: Read, Pull requests: Read+Write, Pipelines: Read" >&2
  fi
  exit 1
fi

if [[ -s "$body_file" ]]; then
  "$CAT_BIN" "$body_file"
fi
