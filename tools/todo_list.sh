#!/bin/bash
if [ ! -f "$TASKS_FILE" ] || [ "$(jq length "$TASKS_FILE")" -eq 0 ]; then
  echo "No tasks."
  exit 0
fi

jq -r '.[] | "\(.id). [\(.status)] \(.desc)"' "$TASKS_FILE"

PENDING=$(jq -r '[.[] | select(.status == "pending")] | length' "$TASKS_FILE")
DONE=$(jq -r '[.[] | select(.status == "done")] | length' "$TASKS_FILE")
echo "--- $PENDING pending, $DONE done ---"
