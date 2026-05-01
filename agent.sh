#!/usr/bin/env bash

set -euo pipefail

MODEL="llama3"   # or whatever you're running
API_URL="http://localhost:11434/api/chat"

SYSTEM_PROMPT="$(cat system.txt)"
HISTORY_FILE="history.json"

# initialize history if missing
if [ ! -f "$HISTORY_FILE" ]; then
  echo '[]' > "$HISTORY_FILE"
fi

call_model() {
  local messages="$1"

  curl -s "$API_URL" \
    -d "{
      \"model\": \"$MODEL\",
      \"stream\": false,
      \"messages\": $messages
    }" | jq -r '.message.content'
}

append_message() {
  local role="$1"
  local content="$2"

  tmp=$(mktemp)
  jq --arg role "$role" --arg content "$content" \
    '. += [{"role": $role, "content": $content}]' \
    "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
}

run_tool() {
  local line="$1"

  # strip prefix
  cmd="${line#TOOL: }"

  tool_name=$(echo "$cmd" | awk '{print $1}')
  args=$(echo "$cmd" | cut -d' ' -f2-)

  tool_path="tools/${tool_name}.sh"

  if [ ! -f "$tool_path" ]; then
    echo "Tool not found: $tool_name"
    return
  fi

  bash "$tool_path" $args
}

build_messages() {
  jq -n \
    --arg system "$SYSTEM_PROMPT" \
    --slurpfile history "$HISTORY_FILE" \
    '[
      {"role":"system","content":$system}
    ] + $history[0]'
}

echo "Agent ready. Type 'exit' to quit."
echo

### Agent Loop
while true; do
  read -rp "> " USER_INPUT

  if [[ "$USER_INPUT" == "exit" ]]; then
    break
  fi

  append_message "user" "$USER_INPUT"

  # inner reasoning loop (tool use loop)
  for i in {1..5}; do
    MESSAGES=$(build_messages)

    RESPONSE=$(call_model "$MESSAGES")

    # check for tool call
    if [[ "$RESPONSE" == TOOL:* ]]; then
      echo "[tool call] $RESPONSE"

      TOOL_OUTPUT=$(run_tool "$RESPONSE")

      append_message "assistant" "$RESPONSE"
      append_message "tool" "$TOOL_OUTPUT"

      continue
    fi

    # final answer
    echo "$RESPONSE"
    append_message "assistant" "$RESPONSE"
    break
  done
done