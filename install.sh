#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "=== Bark Notification Hook for Claude Code ==="
echo ""

# Check for jq (warn only)
if ! command -v jq > /dev/null 2>&1; then
  echo "⚠  jq is not installed. The hook will work but with limited notification details."
  echo "   Install with: brew install jq"
  echo ""
fi

# Prompt for device key
if [ -n "${BARK_DEVICE_KEY:-}" ]; then
  echo "Found BARK_DEVICE_KEY in environment: ${BARK_DEVICE_KEY:0:8}..."
  read -r -p "Use this key? [Y/n] " use_existing
  if [[ "$use_existing" =~ ^[Nn] ]]; then
    BARK_DEVICE_KEY=""
  fi
fi

if [ -z "${BARK_DEVICE_KEY:-}" ]; then
  echo "Open the Bark app on your iPhone to find your device key."
  echo "It's the part after the last / in the server URL shown on the main screen."
  read -r -p "Enter your Bark device key: " BARK_DEVICE_KEY
  if [ -z "$BARK_DEVICE_KEY" ]; then
    echo "Error: device key is required."
    exit 1
  fi
fi

# Copy hook script
echo ""
echo "Installing hook script to $HOOK_DIR/bark-notify.sh ..."
mkdir -p "$HOOK_DIR"
cp "$SCRIPT_DIR/bark-notify.sh" "$HOOK_DIR/bark-notify.sh"
chmod +x "$HOOK_DIR/bark-notify.sh"
echo "✓ Hook script installed"

# Configure settings.json
echo ""
echo "Configuring Claude Code hooks in $SETTINGS_FILE ..."

HOOK_ENTRY='{"matcher":"","hooks":[{"type":"command","command":"'"$HOME"'/.claude/hooks/bark-notify.sh"}]}'

if [ -f "$SETTINGS_FILE" ]; then
  if command -v jq > /dev/null 2>&1; then
    EXISTING=$(cat "$SETTINGS_FILE")

    # Add Stop hook if not already present
    if echo "$EXISTING" | jq -e '.hooks.Stop' > /dev/null 2>&1; then
      # Check if bark-notify.sh is already configured
      if ! echo "$EXISTING" | jq -e '.hooks.Stop[] | .hooks[] | select(.command | contains("bark-notify.sh"))' > /dev/null 2>&1; then
        EXISTING=$(echo "$EXISTING" | jq ".hooks.Stop += [$HOOK_ENTRY]")
      fi
    else
      EXISTING=$(echo "$EXISTING" | jq ".hooks = (.hooks // {}) | .hooks.Stop = [$HOOK_ENTRY]")
    fi

    # Add Notification hook if not already present
    if echo "$EXISTING" | jq -e '.hooks.Notification' > /dev/null 2>&1; then
      if ! echo "$EXISTING" | jq -e '.hooks.Notification[] | .hooks[] | select(.command | contains("bark-notify.sh"))' > /dev/null 2>&1; then
        EXISTING=$(echo "$EXISTING" | jq ".hooks.Notification += [$HOOK_ENTRY]")
      fi
    else
      EXISTING=$(echo "$EXISTING" | jq ".hooks.Notification = [$HOOK_ENTRY]")
    fi

    echo "$EXISTING" | jq '.' > "$SETTINGS_FILE"
  else
    echo "⚠  Cannot auto-configure settings.json without jq."
    echo "   Add these hooks manually to $SETTINGS_FILE:"
    echo ""
    echo '  "hooks": {'
    echo '    "Stop": ['"$HOOK_ENTRY"'],'
    echo '    "Notification": ['"$HOOK_ENTRY"']'
    echo '  }'
    echo ""
  fi
else
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  if command -v jq > /dev/null 2>&1; then
    jq -n "{hooks: {Stop: [$HOOK_ENTRY], Notification: [$HOOK_ENTRY]}}" > "$SETTINGS_FILE"
  else
    echo "{\"hooks\":{\"Stop\":[$HOOK_ENTRY],\"Notification\":[$HOOK_ENTRY]}}" > "$SETTINGS_FILE"
  fi
fi
echo "✓ Hooks configured"

# Write config file
CONF_FILE="$HOOK_DIR/bark-notify.conf"
echo ""
echo "Writing config to $CONF_FILE ..."
cat > "$CONF_FILE" << EOF
BARK_DEVICE_KEY="${BARK_DEVICE_KEY}"
# BARK_SOUND="multiwayinvitation"
# BARK_GROUP="claude-code"
# BARK_SERVER="https://api.day.app"
# BARK_ICON=""
EOF
echo "✓ Config saved"
echo ""
echo "To change settings later, edit: $CONF_FILE"
echo "(Environment variables override config file values)"
echo ""

# Send test notification
echo "Sending test notification..."
BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
RESULT=$(curl -s --max-time 5 \
  -H "Content-Type: application/json" \
  -d "{\"device_key\":\"${BARK_DEVICE_KEY}\",\"title\":\"Claude Code\",\"body\":\"Bark notifications configured successfully!\",\"group\":\"claude-code\",\"sound\":\"${BARK_SOUND:-multiwayinvitation}\"}" \
  "${BARK_SERVER}/push" 2>&1) || true

if echo "$RESULT" | grep -q '"code":200' 2>/dev/null; then
  echo "✓ Test notification sent! Check your phone."
else
  echo "⚠  Test notification may have failed. Response: $RESULT"
  echo "   Verify your device key and try again."
fi

echo ""
echo "=== Setup complete ==="
echo "Claude Code will now notify you via Bark when it completes tasks or needs input."
