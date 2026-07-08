#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jira-comment.sh <ISSUE_KEY> --text <TEXT>
  jira-comment.sh <ISSUE_KEY> --file <PATH>
  jira-comment.sh <ISSUE_KEY> < TEXTFILE
EOF
}

if [[ $# -gt 0 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

script_dir="${0:A:h}"
issue_key="$1"
shift
comment_text=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --text" >&2
        exit 1
      fi
      if [[ -n "$comment_text" ]]; then
        echo "Comment body already provided." >&2
        exit 1
      fi
      comment_text="$2"
      shift 2
      ;;
    --file)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --file" >&2
        exit 1
      fi
      if [[ -n "$comment_text" ]]; then
        echo "Comment body already provided." >&2
        exit 1
      fi
      if [[ ! -f "$2" ]]; then
        echo "File not found: $2" >&2
        exit 1
      fi
      comment_text="$(<"$2")"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$comment_text" && ! -t 0 ]]; then
  comment_text="$(cat)"
fi

if [[ -z "$comment_text" ]]; then
  echo "Comment body is required." >&2
  usage
  exit 1
fi

# Use API v2 here because plain-text comments are simpler than ADF payloads.
payload="$(jq -cn --arg body "$comment_text" '{body:$body}')"

"$script_dir/jira-api.sh" POST "/rest/api/2/issue/${issue_key}/comment" "$payload"
