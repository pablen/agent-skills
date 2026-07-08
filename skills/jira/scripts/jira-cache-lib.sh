#!/bin/zsh

set -euo pipefail

JIRA_CACHE_LIB_DIR="${${(%):-%N}:A:h}"
JIRA_SKILL_ROOT="${JIRA_CACHE_LIB_DIR:h}"
JIRA_DATA_DIR="${JIRA_SKILL_ROOT}/data"

mkdir -p "$JIRA_DATA_DIR"

normalize() {
  print -r -- "${1:-}" |
    /usr/bin/awk '{
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      gsub(/[[:space:]]+/, " ", $0)
      print tolower($0)
    }'
}

cache_path() {
  print -r -- "${JIRA_DATA_DIR}/$1"
}

cache_read() {
  local file
  file="$(cache_path "$1")"

  if [[ -f "$file" ]]; then
    /bin/cat "$file"
  else
    return 1
  fi
}

cache_write() {
  local file tmp
  file="$(cache_path "$1")"
  tmp="$(/usr/bin/mktemp "${file}.tmp.XXXXXX")"
  /bin/cat > "$tmp"
  /bin/mv "$tmp" "$file"
}

cache_mtime() {
  local file
  file="$(cache_path "$1")"

  if [[ ! -f "$file" ]]; then
    print -r -- 0
    return
  fi

  /usr/bin/stat -f '%m' "$file"
}

cache_is_fresh() {
  local key ttl now mtime age
  key="$1"
  ttl="$2"
  now="$(/bin/date +%s)"
  mtime="$(cache_mtime "$key")"
  age=$(( now - mtime ))
  (( mtime > 0 && age < ttl ))
}
