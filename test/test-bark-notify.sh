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

  echo "$input" | HOME="$TMPDIR_TEST" BARK_DEVICE_KEY="test-key-123" PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"

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

  # Check body contains project name and session id
  if ! echo "$body" | jq -e '.body == "my-app (abc123)"' > /dev/null 2>&1; then
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

  echo "$input" | HOME="$TMPDIR_TEST" BARK_DEVICE_KEY="test-key-123" PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"

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

  if ! echo "$body" | jq -e '.body == "web-api (def456)"' > /dev/null 2>&1; then
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

test_custom_sound_and_group() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | \
    HOME="$TMPDIR_TEST" \
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
    HOME="$TMPDIR_TEST" \
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
    HOME="$TMPDIR_TEST" \
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

test_missing_device_key_exits_silently() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | HOME="$TMPDIR_TEST" BARK_DEVICE_KEY="" PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"
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

  echo "$input" | env -u BARK_DEVICE_KEY HOME="$TMPDIR_TEST" PATH="$TMPDIR_TEST/bin:$PATH" bash "$HOOK_SCRIPT"
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

test_reads_device_key_from_config_file() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  # Create a fake HOME with config file
  local fake_home="$TMPDIR_TEST/fakehome"
  mkdir -p "$fake_home/.claude/hooks"
  echo 'BARK_DEVICE_KEY="from-config-file"' > "$fake_home/.claude/hooks/bark-notify.conf"

  echo "$input" | \
    env -u BARK_DEVICE_KEY \
    HOME="$fake_home" \
    PATH="$TMPDIR_TEST/bin:$PATH" \
    bash "$HOOK_SCRIPT"

  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  if ! echo "$body" | jq -e '.device_key == "from-config-file"' > /dev/null 2>&1; then
    echo "FAIL: device_key should come from config file. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}

test_env_var_overrides_config_file() {
  mock_curl_setup
  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  local fake_home="$TMPDIR_TEST/fakehome"
  mkdir -p "$fake_home/.claude/hooks"
  echo 'BARK_DEVICE_KEY="from-config-file"' > "$fake_home/.claude/hooks/bark-notify.conf"

  echo "$input" | \
    HOME="$fake_home" \
    BARK_DEVICE_KEY="from-env-var" \
    PATH="$TMPDIR_TEST/bin:$PATH" \
    bash "$HOOK_SCRIPT"

  if [ ! -f "$TMPDIR_TEST/curl_body" ]; then
    echo "FAIL: curl was not called"
    cleanup
    return 1
  fi

  local body
  body=$(cat "$TMPDIR_TEST/curl_body")

  if ! echo "$body" | jq -e '.device_key == "from-env-var"' > /dev/null 2>&1; then
    echo "FAIL: env var should override config file. Body: $body"
    cleanup
    return 1
  fi

  cleanup
  return 0
}

test_jq_missing_sends_generic_notification() {
  mock_curl_setup

  # Create a fake jq that "doesn't exist" by removing it from PATH
  # We do this by creating a PATH with only our mock curl dir and standard dirs minus jq
  local no_jq_path="$TMPDIR_TEST/bin"
  # Ensure no jq in our mock bin
  rm -f "$TMPDIR_TEST/bin/jq"

  local input='{"hook_event_name":"Stop","cwd":"/Users/me/projects/my-app","session_id":"abc123"}'

  echo "$input" | \
    HOME="$TMPDIR_TEST" \
    BARK_DEVICE_KEY="test-key-123" \
    PATH="$no_jq_path:/bin:/usr/bin" \
    /bin/bash "$HOOK_SCRIPT"

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
