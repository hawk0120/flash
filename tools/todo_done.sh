#!/bin/bash
ID="$1"
if [ -z "$ID" ] || ! [[ "$ID" =~ ^[0-9]+$ ]]; then
  echo "Marks a task done. Usage: todo_done <id>"
  exit 1
fi

if [ ! -f "$TASKS_FILE" ]; then
  echo "No tasks file."
  exit 1
fi

TMP=$(mktemp)
jq "(.[] | select(.id == $ID) | .status) = \"done\"" "$TASKS_FILE" > "$TMP" && mv "$TMP" "$TASKS_FILE"

echo "Task $ID done."
