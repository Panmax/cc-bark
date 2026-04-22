# Bark Notification Hook for Claude Code

Get push notifications on your iPhone via [Bark](https://bark.day.app) when Claude Code finishes a task or needs your input.

## Quick Start

1. Install the [Bark app](https://apps.apple.com/us/app/bark-push-notifications/id1403753865) on your iPhone
2. Copy your device key from the app
3. Run the installer:

```bash
git clone https://github.com/nicr9/cc-bark.git
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
| `BARK_SOUND` | `multiwayinvitation` | Notification sound |
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
