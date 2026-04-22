# Bark Notification Hook for Claude Code

## Overview

A lightweight shell-script hook that sends push notifications to your iOS device via [Bark](https://bark.day.app) when Claude Code finishes work or needs your input.

## Goals

- Notify the user on their phone when Claude Code completes a task (`Stop` event)
- Notify the user when Claude Code needs input or permission (`Notification` event)
- Zero runtime dependencies beyond standard macOS CLI tools (`curl`, `jq`)
- Silent failure — notification errors never block Claude Code

## Architecture

### Files

| File | Purpose |
|------|---------|
| `bark-notify.sh` | Hook script: reads event JSON from stdin, sends Bark push via `curl` |
| `install.sh` | Setup script: copies hook, configures settings.json, prompts for device key |
| `README.md` | Usage and configuration documentation |

### Data Flow

```
Claude Code fires Stop/Notification event
  → Hook system pipes JSON to bark-notify.sh via stdin
  → Script extracts: hook_event_name, cwd
  → Script builds title/body based on event type
  → curl POST to https://api.day.app/push with JSON payload
  → Bark server pushes to iOS device via APNs
```

### Hook Configuration

Added to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/bark-notify.sh"
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
            "command": "~/.claude/hooks/bark-notify.sh"
          }
        ]
      }
    ]
  }
}
```

## Configuration

All configuration via environment variables (set in shell profile):

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BARK_DEVICE_KEY` | Yes | — | Your Bark device key (from the Bark app) |
| `BARK_SERVER` | No | `https://api.day.app` | Bark server URL (for self-hosted) |
| `BARK_SOUND` | No | `multiwayinvitation` | Notification sound name |
| `BARK_GROUP` | No | `claude-code` | Notification group name |
| `BARK_ICON` | No | — | Custom notification icon URL |

## Notification Content

| Event | Title | Body | Level |
|-------|-------|------|-------|
| `Stop` | `Claude Code: Task Complete` | Project directory basename (e.g. "my-app") | `active` |
| `Notification` | `Claude Code: Needs Input` | Project directory basename | `timeSensitive` |

- All notifications grouped under the configured group name (default: `claude-code`)
- `Notification` events use `timeSensitive` level to break through Focus modes
- `Stop` events use `active` level (normal priority)

## Bark API Request

POST to `{BARK_SERVER}/push`:

```json
{
  "device_key": "<BARK_DEVICE_KEY>",
  "title": "Claude Code: Task Complete",
  "body": "my-app",
  "group": "claude-code",
  "sound": "multiwayinvitation",
  "level": "active",
  "icon": "<BARK_ICON if set>"
}
```

## Error Handling

- `BARK_DEVICE_KEY` not set → script exits 0 silently
- `curl` fails (network error) → script exits 0 silently
- `jq` not installed → fall back to hardcoded generic notification ("Claude Code" / "Task finished")
- Hook script always exits 0 to never block Claude Code

## bark-notify.sh Script Logic

```
1. Read JSON from stdin
2. Check BARK_DEVICE_KEY is set, exit 0 if not
3. Extract hook_event_name and cwd from JSON (via jq, or fallback)
4. Determine title and level based on event type:
   - "Stop" → "Claude Code: Task Complete", level=active
   - "Notification" → "Claude Code: Needs Input", level=timeSensitive
   - Other → "Claude Code", level=active
5. Extract project name from cwd (basename)
6. Build JSON payload
7. curl POST to Bark server (timeout 5s, silent, fail silently)
8. Exit 0
```

## install.sh Script Logic

```
1. Check if jq is available, warn if not (non-blocking)
2. Prompt for BARK_DEVICE_KEY
3. Copy bark-notify.sh to ~/.claude/hooks/
4. chmod +x the script
5. Merge hook config into ~/.claude/settings.json (create if needed)
6. Suggest adding BARK_DEVICE_KEY to shell profile
7. Send a test notification to verify setup
```

## Testing

- Manual: Set `BARK_DEVICE_KEY` and pipe test JSON into the script
- Verify Stop event notification arrives
- Verify Notification event notification arrives
- Verify missing BARK_DEVICE_KEY exits silently
- Verify curl failure exits silently
- Verify jq-missing fallback works

## Out of Scope

- Encryption (Bark supports it but adds complexity — can be added later)
- Notification action URLs (tapping notification opens Bark app, not Claude)
- Per-project notification settings
- Rate limiting (Claude Code events are infrequent enough)
