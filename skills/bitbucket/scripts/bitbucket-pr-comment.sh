#!/bin/zsh

# Posts a general or reply comment on a PR.
# Usage: bitbucket-pr-comment.sh <workspace> <repo_slug> <pr_id> <text> [parent_comment_id]

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "Usage: bitbucket-pr-comment.sh <workspace> <repo_slug> <pr_id> <text> [parent_comment_id]" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
pr_id="$3"
text="$4"
parent_id="${5:-}"

if [[ -n "$parent_id" ]]; then
  body="{\"content\":{\"raw\":$(echo -n "$text" | /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')},\"parent\":{\"id\":${parent_id}}}"
else
  body="{\"content\":{\"raw\":$(echo -n "$text" | /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}}"
fi

"$SCRIPT_DIR/bitbucket-api.sh" POST \
  "/2.0/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}/comments" \
  "$body" \
  | /usr/bin/jq -r '"Comment #" + (.id | tostring) + " posted by " + .author.display_name'
