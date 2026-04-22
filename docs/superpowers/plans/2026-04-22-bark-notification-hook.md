# Bark Notification Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shell-script hook that sends Bark push notifications when Claude Code fires `Stop` or `Notification` events.

**Architecture:** A single `bark-notify.sh` reads hook JSON from stdin, extracts event type and working directory, and POSTs to the Bark API via `curl`. An `install.sh` handles copying the hook into place, wiring up `~/.claude/settings.json`, and verifying the setup with a test notification.

**Tech Stack:** Bash, curl, jq (with graceful fallback if jq is missing)

---

## File Structure

```
cc-bark/
├── bark-notify.sh              # Main hook script (reads stdin JSON, calls Bark API)
├── install.sh                  # One-command setup: copies hook, configures settings.json
├── README.md                   # Usage, configuration, troubleshooting
└── test/
    ├── run-tests.sh            # Test runner (executes all test cases, reports pass/fail)
    └── test-bark-notify.sh     # Test cases for bark-notify.sh
```

---

### Task 1: Test infrastructure and first failing test

**Files:**
- Create: `test/run-tests.sh`
- Create: `test/test-bark-notify.sh`
- Create: `bark-notify.sh` (empty stub)

- [ ] **Step 1: Create the test runner**

`test/run-tests.sh` — a minimal test harness that runs test functions and reports results:

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

run_test() {
  local test_name="$1"
  if "$test_name"; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  ✗ ${test_name}"
    printf "  ✗ %s\n" "$test_name"
  fi
}

run_suite() {
  local suite="$1"
  printf "\n%s\n" "$suite"
  source "$suite"
  for fn in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$fn"
    unset -f "$fn"
  done
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for suite in "$SCRIPT_DIR"/test-*.sh; do
  run_suite "$suite"
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "\nFailures:%b\n" "$ERRORS"
  exit 1
fi
```

- [ ] **Step 2: Create the first test — Stop event sends correct Bark payload**

`test/test-bark-notify.sh` — uses a mock `curl` to capture what `bark-notify.sh` would send:

```bash
#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$PROJECT_DIR/bark-notify.sh"
TMPDIR_TEST="$(mktemp -d)"

mock_curl_setup() {
  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/curl" << MOCK
#!/usr/bin/env bash
# Save all args
printf '%s\n' "\$@" > "$TMPDIR_TEST/curl_args"
# Extract -d body
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -d|--data) echo "\$2" > "$TMPDIR_TEST/curl_body"; shift 2 ;;
    *) shift ;;
  esac
done
exit 0
MOCK
  chmod +x "$TMPDIR_TEST/bin/curl"
}

cleanup() {
  rm -rf "$TMPDIR_TEST"
}

test_stop_event_sends_correct_payload() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | BARK_DEVICE_KEY="test-key-123" PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"

  # Verify curl was called
  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  # Check device_key
  if ! echo "$body" | jq -e '.device_key == "test-key-123"' > /dev/null 2>&1; then
    echo "FAIL: device_key mismatch. Body: $body"
    cleanup
    return 1
  fi

  # Check title
  if ! echo "$body" | jq -e '.title == "Claude Code: Task Complete"' > /dev/null 2>&1; then
    echo "FAIL: title mismatch. Body: $body"
    cleanup
    return 1
  fi

  # Check body contains project name
  if ! echo "$body" | jq -e '.body == "my-app"' > /dev/null 2>&1; then
    echo "FAIL: body mismatch. Body: $body"
    cleanup
    return 1
  fi

  # Check level
  if ! echo "$body" | jq -e '.level == "active"' > /dev/null 2>&1; then
    echo "FAIL: level mismatch. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}
```

- [ ] **Step 3: Create empty bark-notify.sh stub**

```bash
#!/usr/bin/env bash
# Bark notification hook for Claude Code
exit 0
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
chmod +x test/run-tests.sh bark-notify.sh
bash test/run-tests.sh
```

Expected: FAIL — `curl was not called`

- [ ] **Step 5: Commit**

```bash
git add test/run-tests.sh test/test-bark-notify.sh bark-notify.sh
git commit -m "test: add test infrastructure and first failing test for Stop event"
```

---

### Task 2: Implement bark-notify.sh core logic (Stop event)

**Files:**
- Modify: `bark-notify.sh`

- [ ] **Step 1: Implement bark-notify.sh with jq-based JSON parsing**

Replace `bark-notify.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)

BARK_DEVICE_KEY="${BARK_DEVICE_KEY:-}"
if [ -z "$BARK_DEVICE_KEY" ]; then
  exit 0
fi

BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
BARK_SOUND="${BARK_SOUND:-multiwayinvitation}"
BARK_GROUP="${BARK_GROUP:-claude-code}"
BARK_ICON="${BARK_ICON:-}"

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
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

PAYLOAD=$(jq -n \
  --arg device_key "$BARK_DEVICE_KEY" \
  --arg title "$TITLE" \
  --arg body "$BODY" \
  --arg group "$BARK_GROUP" \
  --arg sound "$BARK_SOUND" \
  --arg level "$LEVEL" \
  --arg icon "$BARK_ICON" \
  '{
    device_key: $device_key,
    title: $title,
    body: $body,
    group: $group,
    sound: $sound,
    level: $level
  } + (if $icon != "" then {icon: $icon} else {} end)'
)

curl -s -S --fail-with-body \
  --max-time 5 \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "${BARK_SERVER}/push" > /dev/null 2>&1 || true

exit 0
```

- [ ] **Step 2: Run tests to verify Stop event test passes**

```bash
bash test/run-tests.sh
```

Expected: PASS — `test_stop_event_sends_correct_payload`

- [ ] **Step 3: Commit**

```bash
git add bark-notify.sh
git commit -m "feat: implement bark-notify.sh core logic for Stop event"
```

---

### Task 3: Test and implement Notification event handling

**Files:**
- Modify: `test/test-bark-notify.sh`

- [ ] **Step 1: Add Notification event test**

Append to `test/test-bark-notify.sh`:

```bash
test_notification_event_sends_time_sensitive() {
  mock_curl_setup
  local input='{"hook_event_name":"Notification","cwd":"/Users/me/projects/web-api","session_id":"def456"}'

  echo "$input" | BARK_DEVICE_KEY="test-key-123" PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"

  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  if ! echo "$body" | jq -e '.title == "Claude Code: Needs Input"' > /dev/null 2>&1; then
    echo "FAIL: title mismatch. Body: $body"
    cleanup
    return 1
  fi

  if ! echo "$body" | jq -e '.body == "web-api"' > /dev/null 2>&1; then
    echo "FAIL: body mismatch. Body: $body"
    cleanup
    return 1
  fi

  if ! echo "$body" | jq -e '.level == "timeSensitive"' > /dev/null 2>&1; then
    echo "FAIL: level mismatch. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}
```

- [ ] **Step 2: Run tests — should pass since Notification is already implemented**

```bash
bash test/run-tests.sh
```

Expected: 2 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add test/test-bark-notify.sh
git commit -m "test: add Notification event test case"
```

---

### Task 4: Test and implement environment variable configuration

**Files:**
- Modify: `test/test-bark-notify.sh`

- [ ] **Step 1: Add test for custom sound and group**

Append to `test/test-bark-notify.sh`:

```bash
test_custom_sound_and_group() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | \
    BARK_DEVICE_KEY="test-key-123" \
    BARK_SOUND="alarm" \
    BARK_GROUP="work" \
    PATH="$TMPDIR_TEST/bin:$PATH" \
    bash "$HOOK_SCRIPT"

  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  if ! echo "$body" | jq -e '.sound == "alarm"' > /dev/null 2>&1; then
    echo "FAIL: sound mismatch. Body: $body"
    cleanup
    return 1
  fi

  if ! echo "$body" | jq -e '.group == "work"' > /dev/null 2>&1; then
    echo "FAIL: group mismatch. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}

test_custom_icon_included_in_payload() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | \
    BARK_DEVICE_KEY="test-key-123" \
    BARK_ICON="https://example.com/icon.png" \
    PATH="$TMPDIR_TEST/bin:$PATH" \
    bash "$HOOK_SCRIPT"

  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  if ! echo "$body" | jq -e '.icon == "https://example.com/icon.png"' > /dev/null 2>&1; then
    echo "FAIL: icon mismatch. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}

test_no_icon_when_not_set() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | \
    BARK_DEVICE_KEY="test-key-123" \
    BARK_ICON="" \
    PATH="$TMPDIR_TEST/bin:$PATH" \
    bash "$HOOK_SCRIPT"

  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  if echo "$body" | jq -e 'has("icon")' > /dev/null 2>&1; then
    echo "FAIL: icon should not be present. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}
```

- [ ] **Step 2: Run tests — should all pass (env vars already implemented)**

```bash
bash test/run-tests.sh
```

Expected: 5 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add test/test-bark-notify.sh
git commit -m "test: add env var configuration tests (sound, group, icon)"
```

---

### Task 5: Test and implement missing BARK_DEVICE_KEY graceful exit

**Files:**
- Modify: `test/test-bark-notify.sh`

- [ ] **Step 1: Add test for missing device key**

Append to `test/test-bark-notify.sh`:

```bash
test_missing_device_key_exits_silently() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | BARK_DEVICE_KEY="" PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"
  local exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "FAIL: expected exit 0, got $exit_code"
    cleanup
    return 1
  fi

  if [ -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl should NOT have been called"
    cleanup
    return 1
  fi

  cleanup
  return 0
}

test_unset_device_key_exits_silently() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | env -u BARK_DEVICE_KEY PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"
  local exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "FAIL: expected exit 0, got $exit_code"
    cleanup
    return 1
  fi

  if [ -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl should NOT have been called"
    cleanup
    return 1
  fi

  cleanup
  return 0
}
```

- [ ] **Step 2: Run tests — should pass (guard already implemented)**

```bash
bash test/run-tests.sh
```

Expected: 7 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add test/test-bark-notify.sh
git commit -m "test: add missing BARK_DEVICE_KEY tests"
```

---

### Task 6: Test and implement jq-missing fallback

**Files:**
- Modify: `bark-notify.sh`
- Modify: `test/test-bark-notify.sh`

- [ ] **Step 1: Add test for jq-missing fallback**

Append to `test/test-bark-notify.sh`:

```bash
test_jq_missing_sends_generic_notification() {
  mock_curl_setup

  # Create a fake jq that "doesn't exist" by removing it from PATH
  # We do this by creating a PATH with only our mock curl dir and standard dirs minus jq
  local no_jq_path="$TMPDIR_TEST/bin"
  # Ensure no jq in our mock bin
  rm -f "$TMPDIR_TEST/bin/jq"

  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | \
    BARK_DEVICE_KEY="test-key-123" \
    PATH="$no_jq_path" \
    bash "$HOOK_SCRIPT"

  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  # Should contain device_key
  if ! echo "$body" | grep -q "test-key-123"; then
    echo "FAIL: device_key not in payload. Body: $body"
    cleanup
    return 1
  fi

  # Should contain some title
  if ! echo "$body" | grep -q "Claude Code"; then
    echo "FAIL: title not in payload. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}
```

- [ ] **Step 2: Run tests to verify fallback test fails**

```bash
bash test/run-tests.sh
```

Expected: FAIL on `test_jq_missing_sends_generic_notification` — the current script calls `jq` which won't be found.

- [ ] **Step 3: Add jq-missing fallback to bark-notify.sh**

Replace `bark-notify.sh` with the full version that detects jq availability:

```bash
#!/usr/bin/env bash
set -uo pipefail

INPUT=$(cat)

BARK_DEVICE_KEY="${BARK_DEVICE_KEY:-}"
if [ -z "$BARK_DEVICE_KEY" ]; then
  exit 0
fi

BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
BARK_SOUND="${BARK_SOUND:-multiwayinvitation}"
BARK_GROUP="${BARK_GROUP:-claude-code}"
BARK_ICON="${BARK_ICON:-}"

if command -v jq > /dev/null 2>&1; then
  EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Unknown"')
  CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
else
  EVENT="Unknown"
  CWD=""
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

if command -v jq > /dev/null 2>&1; then
  PAYLOAD=$(jq -n \
    --arg device_key "$BARK_DEVICE_KEY" \
    --arg title "$TITLE" \
    --arg body "$BODY" \
    --arg group "$BARK_GROUP" \
    --arg sound "$BARK_SOUND" \
    --arg level "$LEVEL" \
    --arg icon "$BARK_ICON" \
    '{
      device_key: $device_key,
      title: $title,
      body: $body,
      group: $group,
      sound: $sound,
      level: $level
    } + (if $icon != "" then {icon: $icon} else {} end)'
  )
else
  PAYLOAD="{\"device_key\":\"${BARK_DEVICE_KEY}\",\"title\":\"${TITLE}\",\"body\":\"${BODY}\",\"group\":\"${BARK_GROUP}\",\"sound\":\"${BARK_SOUND}\",\"level\":\"${LEVEL}\"}"
fi

curl -s -S --fail-with-body \
  --max-time 5 \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "${BARK_SERVER}/push" > /dev/null 2>&1 || true

exit 0
```

- [ ] **Step 4: Run all tests**

```bash
bash test/run-tests.sh
```

Expected: 8 passed, 0 failed

- [ ] **Step 5: Commit**

```bash
git add bark-notify.sh test/test-bark-notify.sh
git commit -m "feat: add jq-missing fallback for environments without jq"
```

---

### Task 7: Write install.sh

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write the install script**

```bash
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

# Suggest env var setup
echo ""
echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
echo ""
echo "  export BARK_DEVICE_KEY=\"$BARK_DEVICE_KEY\""
echo ""
echo "Optional configuration:"
echo "  export BARK_SOUND=\"multiwayinvitation\"   # notification sound"
echo "  export BARK_GROUP=\"claude-code\"           # notification group"
echo "  export BARK_SERVER=\"https://api.day.app\"  # Bark server URL"
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
```

- [ ] **Step 2: Make it executable and verify it's valid bash**

```bash
chmod +x install.sh
bash -n install.sh
```

Expected: no output (syntax OK)

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh for one-command setup"
```

---

### Task 8: Write README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
# Bark Notification Hook for Claude Code

Get push notifications on your iPhone via [Bark](https://bark.day.app) when Claude Code finishes a task or needs your input.

## Quick Start

1. Install the [Bark app](https://apps.apple.com/us/app/bark-push-notifications/id1403753865) on your iPhone
2. Copy your device key from the app
3. Run the installer:

```bash
git clone https://github.com/YOUR_USERNAME/cc-bark.git
cd cc-bark
BARK_DEVICE_KEY="your-device-key" bash install.sh
```

4. Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export BARK_DEVICE_KEY="your-device-key"
```

5. Restart Claude Code — you'll get notifications automatically.

## What You'll Get

| Event | Notification | Priority |
|-------|-------------|----------|
| Claude finishes a response | "Claude Code: Task Complete" | Normal |
| Claude needs your input/permission | "Claude Code: Needs Input" | Time Sensitive |

Notifications are grouped under "claude-code" in the Bark app.

## Configuration

Set these environment variables to customize behavior:

| Variable | Default | Description |
|----------|---------|-------------|
| `BARK_DEVICE_KEY` | *(required)* | Your Bark device key |
| `BARK_SOUND` | `multiwayinvitation` | Notification sound ([sound list](https://github.com/nicr9/bark-mcp-server)) |
| `BARK_GROUP` | `claude-code` | Notification grouping |
| `BARK_SERVER` | `https://api.day.app` | Bark server URL (for self-hosted) |
| `BARK_ICON` | *(none)* | Custom notification icon URL |

## Manual Installation

If you prefer to install manually:

1. Copy `bark-notify.sh` to `~/.claude/hooks/`:

```bash
mkdir -p ~/.claude/hooks
cp bark-notify.sh ~/.claude/hooks/bark-notify.sh
chmod +x ~/.claude/hooks/bark-notify.sh
```

2. Add hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR_USERNAME/.claude/hooks/bark-notify.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR_USERNAME/.claude/hooks/bark-notify.sh"
          }
        ]
      }
    ]
  }
}
```

3. Set your device key in your shell profile.

## Testing

Run the test suite:

```bash
bash test/run-tests.sh
```

Send a manual test notification:

```bash
echo '{"hook_event_name":"Stop","cwd":"/tmp/test-project"}' | BARK_DEVICE_KEY="your-key" bash bark-notify.sh
```

## Requirements

- macOS or Linux with `curl`
- `jq` recommended (falls back to basic notifications without it)
- [Bark app](https://apps.apple.com/us/app/bark-push-notifications/id1403753865) on your iPhone

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with setup instructions and configuration reference"
```

---

### Task 9: Final integration test

**Files:** *(no new files)*

- [ ] **Step 1: Run the full test suite**

```bash
bash test/run-tests.sh
```

Expected: 8 passed, 0 failed

- [ ] **Step 2: Manual smoke test with real Bark server**

```bash
echo '{"hook_event_name":"Stop","cwd":"/tmp/test-project"}' | BARK_DEVICE_KEY="YOUR_REAL_KEY" bash bark-notify.sh
```

Expected: push notification appears on your phone with title "Claude Code: Task Complete" and body "test-project"

- [ ] **Step 3: Verify bash -n on all scripts**

```bash
bash -n bark-notify.sh
bash -n install.sh
bash -n test/run-tests.sh
bash -n test/test-bark-notify.sh
```

Expected: no output (all syntax valid)

- [ ] **Step 4: Final commit (if any cleanup needed)**

```bash
git log --oneline
```

Verify commit history looks clean.
