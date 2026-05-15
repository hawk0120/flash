#!/bin/bash
DESC="$*"
if [ -z "$DESC" ]; then
  echo "Adds a task. Usage: todo_add <description>"
  exit 1
fi

if [ ! -f "$TASKS_FILE" ]; then
  echo '[]' > "$TASKS_FILE"
fi

MAX_ID=$(jq 'max_by(.id).id // 0' "$TASKS_FILE")
NEW_ID=$((MAX_ID + 1))

TMP=$(mktemp)
jq --arg id "$NEW_ID" --arg desc "$DESC" \
  '. += [{"id": ($id | tonumber), "desc": $desc, "status": "pending"}]' \
  "$TASKS_FILE" > "$TMP" && mv "$TMP" "$TASKS_FILE"

echo "Task $NEW_ID: $DESC [pending]"
