#!/bin/zsh

# Lists open PRs where the current user is author or reviewer.
# Usage: bitbucket-my-prs.sh <workspace> <repo_slug>

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -ne 2 ]]; then
  echo "Usage: bitbucket-my-prs.sh <workspace> <repo_slug>" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"

result=$("$SCRIPT_DIR/bitbucket-api.sh" GET "/2.0/repositories/${workspace}/${repo_slug}/pullrequests?state=OPEN&pagelen=50")

if [[ $(echo "$result" | /usr/bin/jq '.size') -eq 0 ]]; then
  echo "No open PRs found."
  exit 0
fi

echo "$result" | /usr/bin/jq -r '
  ["ID", "Title", "Author", "Source", "State"] | @tsv,
  (.values[] | [
    (.id | tostring),
    .title,
    .author.display_name,
    .source.branch.name,
    .state
  ] | @tsv)
'
