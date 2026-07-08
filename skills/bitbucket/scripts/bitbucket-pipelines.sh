#!/bin/zsh

# Lists pipeline runs, most recent first.
# Usage: bitbucket-pipelines.sh <workspace> <repo_slug> [status] [pagelen]
# status filters on state.result.name: FAILED | SUCCESSFUL | ERROR | STOPPED (omit for all).
# NOTE: the API query param is `status`, not `state` or `result` — those are silently ignored
# (verified against a live repo: both returned unfiltered results with no error).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: bitbucket-pipelines.sh <workspace> <repo_slug> [status] [pagelen]" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
status_filter="${3:-}"
pagelen="${4:-10}"

query="pagelen=${pagelen}&sort=-created_on"
if [[ -n "$status_filter" ]]; then
  query="${query}&status=${status_filter}"
fi

result=$("$SCRIPT_DIR/bitbucket-api.sh" GET "/2.0/repositories/${workspace}/${repo_slug}/pipelines/?${query}")

if [[ $(print -r -- "$result" | /usr/bin/jq '.size') -eq 0 ]]; then
  echo "No pipelines found."
  exit 0
fi

print -r -- "$result" | /usr/bin/jq -r '
  (["Build", "Status", "Branch", "Commit", "Created", "UUID"] | @tsv),
  (.values[] | [
    ("#" + (.build_number | tostring)),
    (.state.result.name // .state.name),
    (.target.ref_name // "?"),
    (.target.commit.hash[0:7] // "?"),
    .created_on,
    .uuid
  ] | @tsv)
'
