#!/bin/zsh

# Merges a PR. Defaults to merge_commit strategy.
# Usage: bitbucket-pr-merge.sh <workspace> <repo_slug> <pr_id> [merge_strategy]
#   merge_strategy: merge_commit (default) | squash | fast_forward

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: bitbucket-pr-merge.sh <workspace> <repo_slug> <pr_id> [merge_strategy]" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
pr_id="$3"
merge_strategy="${4:-merge_commit}"

case "$merge_strategy" in
  merge_commit|squash|fast_forward) ;;
  *)
    echo "Invalid merge_strategy: $merge_strategy. Use merge_commit, squash, or fast_forward." >&2
    exit 1
    ;;
esac

title=$("$SCRIPT_DIR/bitbucket-api.sh" GET \
  "/2.0/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}" \
  | /usr/bin/jq -r '.title')

"$SCRIPT_DIR/bitbucket-api.sh" POST \
  "/2.0/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}/merge" \
  "{\"merge_strategy\": \"${merge_strategy}\", \"message\": \"Merge PR #${pr_id}: ${title}\", \"close_source_branch\": false}" \
  | /usr/bin/jq -r '"Merged: " + .title + "\nCommit: " + .merge_commit.hash'
