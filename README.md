<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Claude Island</h3>
  <p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to Claude Code CLI sessions.
    <br />
    <br />
    <a href="https://github.com/farouqaldori/claude-island/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/farouqaldori/claude-island?style=rounded&color=white&labelColor=000000&label=release" alt="Release Version" />
    </a>
    <a href="#" target="_blank" rel="noopener noreferrer">
      <img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/farouqaldori/claude-island/total?style=rounded&color=white&labelColor=000000">
    </a>
  </p>
</div>

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Live Session Monitoring** — Track multiple Claude Code sessions in real-time
- **Permission Approvals** — Approve or deny tool executions directly from the notch
- **Chat History** — View full conversation history with markdown rendering
- **Auto-Setup** — Hooks install automatically on first launch

## Requirements

- macOS 15.6+
- Claude Code CLI

## Install

Download the latest release or build from source:

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
```

## How It Works

Claude Island installs hooks into `~/.claude/hooks/` that communicate session state via a Unix socket. The app listens for events and displays them in the notch overlay.

When Claude needs permission to run a tool, the notch expands with approve/deny buttons—no need to switch to the terminal.

## OpenCode Hook Compatibility

The OpenCode bridge plugin accepts documented hook names and keeps typed/camelCase aliases for one release. Alias usage is supported with deprecation warnings so integrators can migrate safely.

| Expected hook name | Fallback alias | Required payload fields |
| --- | --- | --- |
| `session.created` | `sessionCreated` | `sessionID` |
| `session.updated` | `sessionUpdated` | `sessionID` |
| `session.idle` | `sessionIdle` | `sessionID` |
| `session.error` | `sessionError` | `sessionID` |
| `session.ended` | `sessionEnded` | `sessionID` |
| `tool.execute.before` | `toolExecuteBefore` | `sessionID`, `callID`, tool name (`tool`) |
| `tool.execute.after` | `toolExecuteAfter` | `sessionID`, `callID`, tool name (`tool`) |
| `permission.ask` | `permissionAsk` | `sessionID`, `callID`, tool name (`tool`) |

## Analytics

Claude Island uses Mixpanel to collect anonymous usage data:

- **App Launched** — App version, build number, macOS version
- **Session Started** — When a new Claude Code session is detected

No personal data or conversation content is collected.

## License

Apache 2.0
