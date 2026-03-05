---
name: spatial-vision
description: Bridges OpenClaw to Apple Vision Pro via WebSocket. Opens floating spatial windows (charts, info cards, web panels) and speaks responses through the Vision Pro headset.
version: 1.0.0
metadata:
  openclaw:
    emoji: "🥽"
    primaryEnv: ANTHROPIC_API_KEY
    requires:
      env:
        - ANTHROPIC_API_KEY
        - OPENAI_API_KEY
      bins:
        - node
    os:
      - macos
      - linux
---

# Spatial Vision — Apple Vision Pro Bridge

This skill runs a WebSocket server on port 7474 that connects to the JarvisVision app on Apple Vision Pro. It receives voice transcripts, routes them through Claude with spatial tool definitions, and broadcasts window payloads back to all connected Vision Pro clients.

## Setup

1. Navigate to the skill scripts directory:
   ```bash
   cd ~/.openclaw/skills/spatial-vision/scripts
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Set environment variables in `~/.openclaw/.env`:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   OPENAI_API_KEY=sk-...
   JARVIS_WS_PORT=7474
   MAC_MINI_IP=192.168.1.50
   ELEVENLABS_API_KEY=...          # Optional — enables premium TTS
   ELEVENLABS_VOICE_ID=pNInz6obpgDQGcFmaJgB  # "Adam" voice
   ```

## Starting the Server

```bash
node ~/.openclaw/skills/spatial-vision/scripts/server.js
```

The WebSocket server will start on the configured port (default 7474).

## Architecture

- **Vision Pro → Mac Mini**: `{ type: "voice_input", transcript: "..." }`
- **Mac Mini → Vision Pro**: `{ type: "open_window" | "speak_response" | "close_all" | "update_window", ... }`

## Available Tools (Claude)

| Tool | Description |
|------|-------------|
| `open_chart_window` | Opens a floating chart (bar, line, area, pie, donut, scatter) |
| `open_info_card` | Opens a markdown info card with optional status badge |
| `open_web_panel` | Opens a web panel with URL or raw HTML |
| `close_all_windows` | Dismisses all open spatial windows |
| `speak_response` | Speaks text through Vision Pro without opening a window |
| `update_window` | Updates an existing window's content |

## Security

- WebSocket runs on LAN only (ws://, no TLS)
- No sensitive data leaves the local network
- API keys stored in environment variables, never in code
