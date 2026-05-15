#!/bin/bash
set -euo pipefail

source config.sh
echo "Models: E2B=$MODEL_E2B  E4B=$MODEL_E4B"
echo "API: $API_URL"

SYSTEM_PROMPT_FILE="system.txt"
SESSIONS_DIR="sessions"
CURRENT_SESSION="default"
HISTORY_FILE="$SESSIONS_DIR/$CURRENT_SESSION.json"
TASKS_FILE="$SESSIONS_DIR/$CURRENT_SESSION.tasks.json"
TOOLS_DIR="tools"

mkdir -p "$TOOLS_DIR" "$SESSIONS_DIR"

if [ -f "history.json" ] && [ ! -f "$HISTORY_FILE" ]; then
  cp "history.json" "$HISTORY_FILE"
fi

if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
  echo '[]' > "$HISTORY_FILE"
fi

if [ ! -f "$TASKS_FILE" ] || [ ! -s "$TASKS_FILE" ]; then
  echo '[]' > "$TASKS_FILE"
fi

if [ -f "$SYSTEM_PROMPT_FILE" ]; then
  SYSTEM_PROMPT=$(cat "$SYSTEM_PROMPT_FILE")
else
  SYSTEM_PROMPT="You are a CLI agent.

Rules:
- If a tool is needed, respond ONLY with:
  TOOL: {\"name\": \"command\", \"args\": [\"arg1\", \"arg2\"]}
- Otherwise respond naturally.
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
  local input
  input=$(echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^\s*$/d')
  if [[ "$input" == TOOL:* ]]; then
    echo "$input" | grep '^TOOL:'
  else
    echo "$input"
  fi
}

run_tool() {
  local line="$1"
  export TASKS_FILE

  local tool_name="${line%% *}"
  local tool_args="${line#* }"
  [ "$tool_name" = "$tool_args" ] && tool_args=""
  local tool_path="$TOOLS_DIR/${tool_name}.sh"

  if [ ! -f "$tool_path" ]; then
    if [ "$tool_name" = "bash" ]; then
      tool_name="sh"
    else
      tool_name="sh"
    fi
    tool_path="$TOOLS_DIR/${tool_name}.sh"
    tool_args="$line"
  fi

  if [ ! -f "$tool_path" ]; then
    echo "Error: Tool not found: ${line%% *}"
    return 1
  fi

  "$tool_path" $tool_args
}

build_tools() {
  cat <<'EOF'
[
  {"type":"function","function":{"name":"sh","description":"Run any shell command","parameters":{"type":"object","properties":{"command":{"type":"string","description":"Shell command to execute"}},"required":["command"]}}},
  {"type":"function","function":{"name":"webfetch","description":"Fetch a URL and return text content. Use this to research topics online.","parameters":{"type":"object","properties":{"url":{"type":"string","description":"The URL to fetch"}},"required":["url"]}}},
  {"type":"function","function":{"name":"todo_add","description":"Add a task to the todo list","parameters":{"type":"object","properties":{"description":{"type":"string","description":"Task description"}},"required":["description"]}}},
  {"type":"function","function":{"name":"todo_done","description":"Mark a task as complete","parameters":{"type":"object","properties":{"id":{"type":"number","description":"Task ID"}},"required":["id"]}}},
  {"type":"function","function":{"name":"todo_list","description":"Show all tasks and their status","parameters":{"type":"object","properties":{}}}}
]
EOF
}

execute_tool() {
  local name="$1"
  local args="$2"
  export TASKS_FILE

  case "$name" in
    sh)
      local cmd; cmd=$(echo "$args" | jq -r '.command // ""')
      [ -z "$cmd" ] && return
      bash -c "$cmd" 2>&1 || echo "Command failed (exit: $?)"
      ;;
    webfetch)
      local url; url=$(echo "$args" | jq -r '.url // ""')
      [ -z "$url" ] && return
      "$TOOLS_DIR/webfetch.sh" "$url"
      ;;
    todo_add)
      local desc; desc=$(echo "$args" | jq -r '.description // ""')
      [ -z "$desc" ] && return
      "$TOOLS_DIR/todo_add.sh" "$desc"
      ;;
    todo_done)
      local id; id=$(echo "$args" | jq -r '.id // ""')
      [ -z "$id" ] && return
      "$TOOLS_DIR/todo_done.sh" "$id"
      ;;
    todo_list)
      "$TOOLS_DIR/todo_list.sh"
      ;;
    *)
      echo "Unknown tool: $name"
      return 1
      ;;
  esac
}

append_message_json() {
  local msg_json="$1"
  local tmp; tmp=$(mktemp)
  jq ". += [$msg_json]" "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
}


# ----  call_Model() -----------
call_model() {
    local messages_json="$1"
    local model="$2"
    local use_tools="$3"
    local tools_json=""

    if [ "$use_tools" = "true" ]; then
      tools_json=",\"tools\": $(build_tools)"
    fi

    curl -s "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model\",
            \"stream\": false,
            \"messages\": $messages_json
            $tools_json
        }"
}

# --- Main loop ---
echo "Agent ready. Type 'exit' to quit. Session: $CURRENT_SESSION"
echo

while true; do
  read -rp "[$CURRENT_SESSION] " USER_INPUT

  case "$USER_INPUT" in
    exit|quit)
      break
      ;;
    /session\ *)
      SESSION_NAME="${USER_INPUT#/session }"
      if [ -n "$SESSION_NAME" ]; then
        if [[ "$SESSION_NAME" =~ ^[0-9]+$ ]]; then
          idx=0
          found=""
          for f in "$SESSIONS_DIR"/*.json; do
            [[ "$f" != *.tasks.json ]] || continue
            [ -f "$f" ] || continue
            if [ "$idx" -eq "$SESSION_NAME" ]; then
              found=$(basename "$f" .json)
              break
            fi
            idx=$((idx + 1))
          done
          if [ -n "$found" ]; then
            SESSION_NAME="$found"
          else
            echo "Session index $SESSION_NAME not found"
            continue
          fi
        fi
        CURRENT_SESSION="$SESSION_NAME"
        HISTORY_FILE="$SESSIONS_DIR/$CURRENT_SESSION.json"
        TASKS_FILE="$SESSIONS_DIR/$CURRENT_SESSION.tasks.json"
        if [ ! -f "$HISTORY_FILE" ]; then
          echo '[]' > "$HISTORY_FILE"
        fi
        if [ ! -f "$TASKS_FILE" ]; then
          echo '[]' > "$TASKS_FILE"
        fi
        echo "Switched to session: $CURRENT_SESSION"
      else
        echo "Usage: /session <name or index>"
      fi
      continue
      ;;
    /sessions)
      echo "Sessions:"
      idx=0
      for f in "$SESSIONS_DIR"/*.json; do
        [[ "$f" != *.tasks.json ]] || continue
        [ -f "$f" ] || continue
        name=$(basename "$f" .json)
        count=$(jq length "$f")
        marker=""
        [ "$name" = "$CURRENT_SESSION" ] && marker=" <-- current"
        echo "  $idx) $name ($count messages)$marker"
        idx=$((idx + 1))
      done
      continue
      ;;
    /new)
      echo '[]' > "$HISTORY_FILE"
      echo "Cleared session: $CURRENT_SESSION"
      continue
      ;;
  esac

  append_message "user" "$USER_INPUT"

  TOOL_WAS_CALLED=false

  for ((i=0; i<200; i++)); do
    MESSAGES=$(build_messages)

    # Call E4B with tools for decision-making
    E4B_RESPONSE=$(call_model "$MESSAGES" "$MODEL_E4B" "true")
    CONTENT=$(echo "$E4B_RESPONSE" | jq -r '.message.content // ""')
    TOOL_CALLS=$(echo "$E4B_RESPONSE" | jq -c '.message.tool_calls // [] | .[]')

    if [ -n "$TOOL_CALLS" ]; then
      TOOL_WAS_CALLED=true

      ASST_MSG=$(echo "$E4B_RESPONSE" | jq -c '{role: "assistant", content: .message.content, tool_calls: .message.tool_calls}')
      append_message_json "$ASST_MSG"

      TC_NAMES=(); TC_ARGS=(); TC_FILES=(); TC_PIDS=()

      while IFS= read -r tc; do
        [ -z "$tc" ] && continue
        NAME=$(echo "$tc" | jq -r '.function.name')
        ARGS=$(echo "$tc" | jq -c '.function.arguments')
        TMP=$(mktemp)

        (
          execute_tool "$NAME" "$ARGS" > "$TMP" 2>&1
        ) &

        TC_NAMES+=("$NAME"); TC_ARGS+=("$ARGS")
        TC_FILES+=("$TMP"); TC_PIDS+=($!)
      done <<< "$TOOL_CALLS"

      for pid in "${TC_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
      done

      for i in "${!TC_FILES[@]}"; do
        NAME="${TC_NAMES[$i]}"
        ARGS="${TC_ARGS[$i]}"
        FILE="${TC_FILES[$i]}"
        OUTPUT=$(cat "$FILE")
        rm -f "$FILE"

        echo
        echo "[$NAME] $ARGS"
        if [ -n "$OUTPUT" ]; then
          echo "$OUTPUT"
        fi

        append_message_json "$(jq -n --arg c "$OUTPUT" --arg n "$NAME" '{role: "tool", content: $c, name: $n}')"
      done
      continue
    fi

    # E4B returned text (no more tools needed)
    if [ "$TOOL_WAS_CALLED" = true ]; then
      # Tools were used — route to E2B for final text response
      E2B_RAW=$(call_model "$MESSAGES" "$MODEL_E2B" "false")
      E2B_TEXT=$(echo "$E2B_RAW" | jq -r '.message.content // ""')
      if [ -n "$E2B_TEXT" ]; then
        echo
        echo "$E2B_TEXT"
        append_message "assistant" "$E2B_TEXT"
      fi
    else
      # No tools needed — use E4B's text directly
      if [ -n "$CONTENT" ]; then
        echo
        echo "$CONTENT"
        append_message "assistant" "$CONTENT"
      fi
    fi
    break
  done
done
