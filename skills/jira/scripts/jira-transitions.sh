#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: jira-transitions.sh <ISSUE_KEY>" >&2
  exit 1
fi

script_dir="${0:A:h}"
issue_key="$1"

"$script_dir/jira-api.sh" GET "/rest/api/3/issue/${issue_key}/transitions" |
  jq -r '.transitions[] | [ .id, .name, (.to.name // "") ] | @tsv'
