#!/bin/zsh

set -euo pipefail

if [[ -f "$HOME/.jira-env" ]]; then
  source "$HOME/.jira-env"
fi

if [[ -z "${JIRA_URL:-}" ]]; then
  echo "Missing Jira URL. Expected JIRA_URL." >&2
  exit 1
fi

base_url="${JIRA_URL%/}"

if [[ $# -eq 1 && "$1" == "--base" ]]; then
  printf '%s\n' "$base_url"
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: jira-browse-url.sh --base | jira-browse-url.sh <ISSUE_KEY> [COMMENT_ID]" >&2
  exit 1
fi

issue_key="$1"
comment_id="${2:-}"

if [[ -n "$comment_id" ]]; then
  printf '%s/browse/%s?focusedCommentId=%s\n' "$base_url" "$issue_key" "$comment_id"
else
  printf '%s/browse/%s\n' "$base_url" "$issue_key"
fi
