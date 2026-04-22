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
