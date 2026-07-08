#!/bin/zsh

# Approves a PR. Uses Bearer auth with BITBUCKET_API_TOKEN (Repository Access Token).
# Token must have Pull requests: Write scope.
# Usage: bitbucket-pr-approve.sh <workspace> <repo_slug> <pr_id>

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -ne 3 ]]; then
  echo "Usage: bitbucket-pr-approve.sh <workspace> <repo_slug> <pr_id>" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
pr_id="$3"

"$SCRIPT_DIR/bitbucket-api.sh" POST \
  "/2.0/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}/approve" \
  | /usr/bin/jq -r '"Approved by: " + .user.display_name'
