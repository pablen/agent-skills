#!/bin/zsh

# Prints all PR comments (inline and general) in a readable format.
# Usage: bitbucket-pr-comments.sh <workspace> <repo_slug> <pr_id>

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -ne 3 ]]; then
  echo "Usage: bitbucket-pr-comments.sh <workspace> <repo_slug> <pr_id>" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
pr_id="$3"

path="/2.0/repositories/${workspace}/${repo_slug}/pullrequests/${pr_id}/comments?pagelen=100"

"$SCRIPT_DIR/bitbucket-api.sh" GET "$path" | /usr/bin/jq -r '
  .values[]
  | select(.deleted == false)
  | [
      "---",
      ("Author: " + .author.display_name),
      ("Date:   " + .created_on[:19]),
      (if .inline then
        "File:   " + .inline.path +
        (if .inline.to then " (line " + (.inline.to | tostring) + ")" else "" end)
      else
        "Type:   general comment"
      end),
      (if .parent then "Reply to comment #" + (.parent.id | tostring) else "" end),
      "",
      .content.raw
    ]
  | map(select(. != ""))
  | join("\n")
'
