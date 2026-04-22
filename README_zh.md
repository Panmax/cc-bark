# Bark 通知 Hook - Claude Code

[English](README.md) | [中文](README_zh.md)

当 Claude Code 完成任务或需要你的输入时，通过 [Bark](https://bark.day.app) 向你的 Apple 设备发送推送通知。

## 快速开始

1. 在 iPhone 或 Mac 上安装 [Bark App](https://apps.apple.com/us/app/bark-push-notifications/id1403753865)
2. 从 App 中复制你的设备密钥（Device Key）
3. 运行安装脚本：

```bash
git clone https://github.com/Panmax/cc-bark.git
cd cc-bark
BARK_DEVICE_KEY="你的设备密钥" bash install.sh
```

4. 将以下内容添加到你的 Shell 配置文件（`~/.zshrc` 或 `~/.bashrc`）：

```bash
export BARK_DEVICE_KEY="你的设备密钥"
```

5. 重启 Claude Code，之后你将自动收到通知。

## 通知效果

| 事件 | 通知内容 | 优先级 |
|------|---------|--------|
| Claude 完成响应 | "Claude Code: Task Complete" | 普通 |
| Claude 需要你的输入/授权 | "Claude Code: Needs Input" | 时效性（可突破专注模式） |

所有通知在 Bark App 中归类在 "claude-code" 分组下。

## 配置

通过环境变量自定义通知行为：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `BARK_DEVICE_KEY` | *（必填）* | Bark 设备密钥 |
| `BARK_SOUND` | `multiwayinvitation` | 通知提示音 |
| `BARK_GROUP` | `claude-code` | 通知分组名称 |
| `BARK_SERVER` | `https://api.day.app` | Bark 服务器地址（自建服务器时使用） |
| `BARK_ICON` | *（无）* | 自定义通知图标 URL |

## 手动安装

如果你更喜欢手动安装：

1. 将 `bark-notify.sh` 复制到 `~/.claude/hooks/`：

```bash
mkdir -p ~/.claude/hooks
cp bark-notify.sh ~/.claude/hooks/bark-notify.sh
chmod +x ~/.claude/hooks/bark-notify.sh
```

2. 在 `~/.claude/settings.json` 中添加 Hook 配置：

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/你的用户名/.claude/hooks/bark-notify.sh"
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
            "command": "/Users/你的用户名/.claude/hooks/bark-notify.sh"
          }
        ]
      }
    ]
  }
}
```

3. 在 Shell 配置文件中设置设备密钥。

## 测试

运行测试套件：

```bash
bash test/run-tests.sh
```

手动发送测试通知：

```bash
echo '{"hook_event_name":"Stop","cwd":"/tmp/test-project"}' | BARK_DEVICE_KEY="你的密钥" bash bark-notify.sh
```

## 系统要求

- macOS 或 Linux（需要 `curl`）
- 建议安装 `jq`（未安装时会降级为基础通知）
- iPhone 或 Mac 上安装 [Bark App](https://apps.apple.com/us/app/bark-push-notifications/id1403753865)

## 许可证

MIT
