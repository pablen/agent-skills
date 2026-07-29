#!/bin/zsh

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  jira-markdown-to-adf.sh --text <MARKDOWN>
  jira-markdown-to-adf.sh --file <PATH>
  jira-markdown-to-adf.sh < MARKDOWN_FILE

Supports headings, paragraphs, bullet lists and Jira task checklists.
EOF
}

text=""
file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      text="${2:-}"
      shift 2
      ;;
    --file)
      file="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$text" && -n "$file" ]]; then
  echo "Use only one of --text or --file." >&2
  exit 1
fi

if [[ -n "$file" ]]; then
  if [[ ! -f "$file" ]]; then
    echo "File not found: $file" >&2
    exit 1
  fi
  text="$(<"$file")"
elif [[ -z "$text" && ! -t 0 ]]; then
  text="$(cat)"
fi

if [[ -z "$text" ]]; then
  echo "Markdown content is required." >&2
  usage
  exit 1
fi

print -r -- "$text" | jq -Rs '
  def text_node($value): {type: "text", text: $value};
  def paragraph($value): {type: "paragraph", content: [text_node($value)]};
  def flush_list:
    if (.list | length) > 0 then
      if .list_type == "task" then
        .task_list_index as $index
        | .content += [
            {
              type: "taskList",
              attrs: {localId: "task-list-\($index)"},
              content: (
                .list
                | to_entries
                | map({
                    type: "taskItem",
                    attrs: {
                      localId: "task-\($index)-\(.key)",
                      state: .value.state
                    },
                    content: [text_node(.value.text)]
                  })
              )
            }
          ]
        | .task_list_index += 1
      else
        .content += [
          {
            type: "bulletList",
            content: (.list | map({type: "listItem", content: [paragraph(.)]}))
          }
        ]
      end
      | .list = []
      | .list_type = null
    else
      .
    end;
  reduce (gsub("\r\n"; "\n") | split("\n"))[] as $line
    ({content: [], list: [], list_type: null, task_list_index: 0};
      if ($line | test("^#{1,6}[[:space:]]+")) then
        flush_list
        | ($line | capture("^(?<markers>#{1,6})[[:space:]]+(?<value>.*)$")) as $heading
        | .content += [
            {
              type: "heading",
              attrs: {level: ($heading.markers | length)},
              content: [text_node($heading.value)]
            }
          ]
      elif ($line | test("^- \\[([ xX])\\][[:space:]]*")) then
        if .list_type != null and .list_type != "task" then flush_list else . end
        | ($line | capture("^- \\[(?<state>[ xX])\\][[:space:]]*(?<text>.*)$")) as $task
        | .list_type = "task"
        | .list += [{
            state: (if ($task.state | test("[xX]")) then "DONE" else "TODO" end),
            text: $task.text
          }]
      elif ($line | test("^- ")) then
        if .list_type != null and .list_type != "bullet" then flush_list else . end
        | .list_type = "bullet"
        | .list += [($line | sub("^- [[:space:]]*"; ""))]
      elif $line == "" then
        flush_list
      else
        flush_list | .content += [paragraph($line)]
      end
    )
  | flush_list
  | {type: "doc", version: 1, content: .content}
'
