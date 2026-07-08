#!/bin/zsh

# Prints PR summary: title, state, author, reviewers, description.
# Usage: bitbucket-pr.sh <workspace> <repo_slug> <pr_id>

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -ne 3 ]]; then
  echo "Usage: bitbucket-pr.sh <workspace> <repo_slug> <pr_id>" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
pr_id="$3"

"$SCRIPT_DIR/bitbucket-api.sh" GET "/2.0/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}" | /usr/bin/jq -r '
  "Title:       " + .title,
  "State:       " + .state,
  "Author:      " + .author.display_name,
  "Source:      " + .source.branch.name,
  "Destination: " + .destination.branch.name,
  "URL:         " + .links.html.href,
  "",
  "Reviewers:",
  (.reviewers[] | "  - " + .display_name + " (" + (if .approved then "approved" else "pending" end) + ")"),
  "",
  "Description:",
  (.description // "(none)")
'
