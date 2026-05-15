#!/bin/bash
URL="$1"
if [ -z "$URL" ]; then
  echo "Fetches a URL and returns the content as text."
  echo "Usage: webfetch <url>"
  exit 1
fi

curl -sL --max-time 15 "$URL" | sed 's/<[^>]*>//g' | sed '/^\s*$/d' | head -n 200
