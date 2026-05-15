#!/bin/bash

MODEL_E2B="${MODEL_E2B:-Qwen3-4B-Thinking-2507-GGUF:UD-Q4_K_XL}"
MODEL_E4B="${MODEL_E4B:-Qwen3-4B-Thinking-2507-GGUF:UD-Q4_K_XL}"

API_URL="${API_URL:-http://localhost:11434/api/chat}"