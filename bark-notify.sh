#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)

CONF_FILE="${HOME}/.claude/hooks/bark-notify.conf"
if [ -f "$CONF_FILE" ]; then
  _pre_key="${BARK_DEVICE_KEY:-}"
  _pre_server="${BARK_SERVER:-}"
  _pre_group="${BARK_GROUP:-}"
  _pre_icon="${BARK_ICON:-}"
  source "$CONF_FILE"
  [ -n "$_pre_key" ] && BARK_DEVICE_KEY="$_pre_key"
  [ -n "$_pre_server" ] && BARK_SERVER="$_pre_server"
  [ -n "$_pre_group" ] && BARK_GROUP="$_pre_group"
  [ -n "$_pre_icon" ] && BARK_ICON="$_pre_icon"
fi

BARK_DEVICE_KEY="${BARK_DEVICE_KEY:-}"
if [ -z "$BARK_DEVICE_KEY" ]; then
  exit 0
fi

BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
BARK_GROUP="${BARK_GROUP:-claude-code}"
BARK_ICON="${BARK_ICON:-}"

if command -v jq > /dev/null 2>&1; then
  EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Unknown"')
  CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
else
  EVENT="Unknown"
  CWD=""
  SESSION_ID=""
fi

PROJECT=$(basename "$CWD")

case "$EVENT" in
  Stop)
    TITLE="Claude Code: Task Complete"
    LEVEL="active"
    ;;
  Notification)
    TITLE="Claude Code: Needs Input"
    LEVEL="timeSensitive"
    ;;
  *)
    TITLE="Claude Code"
    LEVEL="active"
    ;;
esac

BODY="${PROJECT:-Claude Code}"
if [ -n "$SESSION_ID" ]; then
  SHORT_ID="${SESSION_ID:0:8}"
  BODY="${BODY} (${SHORT_ID})"
fi

if command -v jq > /dev/null 2>&1; then
  PAYLOAD=$(jq -n \
    --arg device_key "$BARK_DEVICE_KEY" \
    --arg title "$TITLE" \
    --arg body "$BODY" \
    --arg group "$BARK_GROUP" \
    --arg level "$LEVEL" \
    --arg icon "$BARK_ICON" \
    '{
      device_key: $device_key,
      title: $title,
      body: $body,
      group: $group,
      level: $level
    } + (if $icon != "" then {icon: $icon} else {} end)'
  )
else
  PAYLOAD="{\"device_key\":\"${BARK_DEVICE_KEY}\",\"title\":\"${TITLE}\",\"body\":\"${BODY}\",\"group\":\"${BARK_GROUP}\",\"level\":\"${LEVEL}\"}"
fi

curl -s -S --fail-with-body \
  --max-time 5 \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "${BARK_SERVER}/push" > /dev/null 2>&1 || true

exit 0
