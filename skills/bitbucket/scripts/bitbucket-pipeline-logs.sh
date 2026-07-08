#!/bin/zsh

# Prints the raw logs of a single pipeline step.
# The /log endpoint returns plain text, not JSON — this script calls curl directly.
# Usage: bitbucket-pipeline-logs.sh <workspace> <repo_slug> <pipeline_uuid> <step_uuid>

set -euo pipefail

# ── Credentials (same logic as bitbucket-api.sh) ──
BITBUCKET_API_TOKEN="${BITBUCKET_API_TOKEN:-}"
if [[ -f "./.bitbucket-token" ]]; then
  source "./.bitbucket-token"
elif [[ -f "$HOME/.bitbucket-env" ]]; then
  source "$HOME/.bitbucket-env"
fi

if [[ -z "${BITBUCKET_API_TOKEN:-}" ]]; then
  echo "Missing Bitbucket credentials." >&2
  echo "" >&2
  echo "Create a Repository Access Token:" >&2
  echo "  1. Go to https://bitbucket.org/<WORKSPACE>/<REPO>/admin/access-tokens" >&2
  echo "  2. Create token with scopes: Repositories: Read, Pull requests: Read+Write, Pipelines: Read" >&2
  echo "  3. Save it in ./.bitbucket-token (repo-local, recommended) or ~/.bitbucket-env (global):" >&2
  echo "" >&2
  echo "     BITBUCKET_API_TOKEN=<your-token>" >&2
  echo "" >&2
  exit 1
fi

if [[ $# -ne 4 ]]; then
  echo "Usage: bitbucket-pipeline-logs.sh <workspace> <repo_slug> <pipeline_uuid> <step_uuid>" >&2
  exit 1
fi

workspace="$1"
repo_slug="$2"
pipeline_uuid="$3"
step_uuid="$4"

# URL-encode the UUIDs (they contain braces)
encoded_pipeline=$(echo -n "$pipeline_uuid" | /usr/bin/jq -sRr '@uri')
encoded_step=$(echo -n "$step_uuid" | /usr/bin/jq -sRr '@uri')

# Fetch step metadata first to show context (use bitbucket-api.sh for JSON)
SCRIPT_DIR="${0:A:h}"
step_info=$("$SCRIPT_DIR/bitbucket-api.sh" GET \
  "/2.0/repositories/${workspace}/${repo_slug}/pipelines/${encoded_pipeline}/steps/${encoded_step}" 2>/dev/null || echo "")

if [[ -n "$step_info" ]]; then
  print -r -- "$step_info" | /usr/bin/jq -r '
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "Step:     " + .name,
    "State:    " + .state.result.name,
    "Duration: " + (.duration_in_seconds | tostring) + "s",
    "Pipeline: " + (.pipeline.uuid // "?"),
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    ""
  ' 2>/dev/null || true
fi

# The /log endpoint returns text/plain. Using Accept: application/json causes 406.
/usr/bin/curl -sS -L \
  -H "Authorization: Bearer $BITBUCKET_API_TOKEN" \
  "https://api.bitbucket.org/2.0/repositories/${workspace}/${repo_slug}/pipelines/${encoded_pipeline}/steps/${encoded_step}/log"
