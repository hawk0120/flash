#!/bin/bash
set -euo pipefail

source config.sh
echo "Model: $MODEL"
echo "API: $API_URL"

SYSTEM_PROMPT_FILE="system.txt"
HISTORY_FILE="history.json"
TOOLS_DIR="tools"

mkdir -p "$TOOLS_DIR"

if [ ! -f "$HISTORY_FILE" ]; then
  echo '[]' > "$HISTORY_FILE"
fi

if [ -f "$SYSTEM_PROMPT_FILE" ]; then
  SYSTEM_PROMPT=$(cat "$SYSTEM_PROMPT_FILE")
else
  SYSTEM_PROMPT="You are a CLI agent.

Rules:
- If a tool is needed, respond ONLY with:
  TOOL: {\"name\": \"command\", \"args\": [\"arg1\", \"arg2\"]}
- Otherwise respond in 1 short sentence.
- Never explain tool usage.

Available tools: ls, cat, grep, echo, curl, jq"
  echo "$SYSTEM_PROMPT" > "$SYSTEM_PROMPT_FILE"
fi

append_message() {
  local role="$1"
  local content="$2"
  local tmp
  tmp=$(mktemp)

  jq --arg role "$role" --arg content "$content" \
    '. += [{"role": $role, "content": $content}]' \
    "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
}

build_messages() {
  jq -n \
    --arg system "$SYSTEM_PROMPT" \
    --slurpfile history "$HISTORY_FILE" \
    '[{"role":"system","content":$system}] + $history[0]'
}

normalize_response() {
  echo "$1" | sed '/^\s*$/d' | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

run_tool() {
  local line="$1"

  # Strip prefix safely
  local cmd="${line#TOOL: bash_ }"

  # Split into array safely (no word splitting bugs)
  local args=()
  while IFS= read -r word; do
    args+=("$word")
  done <<< "$cmd"

  local tool_path="$TOOLS_DIR/bash_.sh"

  if [ ! -f "$tool_path" ]; then
    echo "Error: Tool not found: bash_"
    return 1
  fi

  # Execute safely with proper argument handling
  "$tool_path" "${args[@]}"
}
call_model() {
  local messages_json="$1"

  curl -s "$API_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$MODEL\",
      \"stream\": false,
      \"messages\": $messages_json
    }" | jq -r '.message.content'
}

# --- Main loop ---
echo "Agent ready. Type 'exit' to quit."
echo

while true; do
  read -rp "> " USER_INPUT

  case "$USER_INPUT" in
    exit|quit)
      break
      ;;
  esac

  append_message "user" "$USER_INPUT"

  for i in {1..5}; do
    MESSAGES=$(build_messages)
    RAW_RESPONSE=$(call_model "$MESSAGES")

    RESPONSE=$(normalize_response "$RAW_RESPONSE")

    # --- Tool call detection ---
    if [[ "$RESPONSE" == TOOL:* ]]; then
      echo
      echo "[tool call] $RESPONSE"

      TOOL_JSON=$(echo "$RESPONSE" | sed 's/^TOOL: //')

      TOOL_OUTPUT=$(run_tool "$TOOL_JSON" || echo "Tool execution failed")

      append_message "assistant" "$RESPONSE"
      append_message "tool" "$TOOL_OUTPUT"

      continue
    fi

    # --- Final answer ---
    echo
    echo "$RAW_RESPONSE"
    append_message "assistant" "$RAW_RESPONSE"
    break
  done
done
