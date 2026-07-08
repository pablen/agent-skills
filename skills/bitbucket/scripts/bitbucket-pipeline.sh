#!/bin/zsh

# Prints pipeline summary and its steps (with step UUIDs, for use with bitbucket-pipeline-logs.sh).
# Usage: bitbucket-pipeline.sh <workspace> <repo_slug> <pipeline_uuid>

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -ne 3 ]]; then
  echo "Usage: bitbucket-pipeline.sh <workspace> <repo_slug> <pipeline_uuid>" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
pipeline_uuid="$3"

# URL-encode the UUID (it contains braces)
encoded_uuid=$(echo -n "$pipeline_uuid" | /usr/bin/jq -sRr '@uri')

pipeline=$("$SCRIPT_DIR/bitbucket-api.sh" GET "/2.0/repositories/${workspace}/${repo_slug}/pipelines/${encoded_uuid}")

print -r -- "$pipeline" | /usr/bin/jq -r '
  "Build:    #" + (.build_number | tostring),
  "Status:   " + (.state.result.name // .state.name),
  "Branch:   " + (.target.ref_name // "?"),
  "Commit:   " + (.target.commit.hash[0:7] // "?"),
  "Created:  " + .created_on,
  "Trigger:  " + (.trigger.name // "?"),
  ""
'

echo "Steps:"
"$SCRIPT_DIR/bitbucket-api.sh" GET "/2.0/repositories/${workspace}/${repo_slug}/pipelines/${encoded_uuid}/steps/" | /usr/bin/jq -r '
  (.values[] | "  - " + .name + "  [" + (.state.result.name // .state.name) + "]  (" + (.duration_in_seconds | tostring) + "s)  uuid=" + .uuid)
'
