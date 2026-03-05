# Project Jarvis

Spatial AI Assistant — Apple Vision Pro + OpenClaw + Mac Mini

Jarvis is a personal spatial AI assistant that combines Apple Vision Pro's mixed-reality display with OpenClaw's agent framework running on a Mac Mini. Speak a command, and floating windows materialize in your field of view — charts, info cards, and web panels — all orchestrated by Claude as the reasoning engine.

## Architecture

```
┌─────────────────────────────────┐      ┌──────────────────────────────────────┐
│       APPLE VISION PRO           │      │           MAC MINI M4 PRO            │
│                                 │      │                                      │
│  [Mic] → Whisper STT            │      │  OpenClaw + Spatial Vision Skill     │
│       → WebSocket ──────────────┼─────→│    ├── Claude API (tool router)      │
│                                 │      │    ├── Caddis CMMS MCP               │
│  [Spatial Windows] ◄────────────┼──────┤    ├── Epicor / Jobcost MCP          │
│    ├── Chart Window             │      │    └── Industrial Server MCP         │
│    ├── Info Card Window         │      │                                      │
│    └── Web Panel Window         │      │  WebSocket server on port 7474       │
└─────────────────────────────────┘      └──────────────────────────────────────┘
              LAN (Wi-Fi 6 / Ethernet)
```

## Prerequisites

- **Mac Mini M4 Pro** (or any Mac) with Node.js 22+
- **Apple Vision Pro** with Developer Mode enabled
- **Xcode 15+** (for building the visionOS app)
- **Anthropic API key** ([console.anthropic.com](https://console.anthropic.com))
- **OpenAI API key** ([platform.openai.com](https://platform.openai.com)) — for Whisper STT

## Setup — Mac Mini Backend

### 1. Install OpenClaw

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

### 2. Install the Spatial Vision Skill

```bash
# Copy skill to OpenClaw skills directory
cp -r mac-mini/skills/spatial-vision ~/.openclaw/skills/

# Install Node.js dependencies for the skill server
cd ~/.openclaw/skills/spatial-vision/scripts
npm install
```

### 3. Configure Environment

```bash
# Copy the example env file
cp mac-mini/.env.example ~/.openclaw/.env

# Edit with your actual keys
nano ~/.openclaw/.env
```

Required variables:
```
ANTHROPIC_API_KEY=sk-ant-your-key-here
OPENAI_API_KEY=sk-your-key-here
JARVIS_WS_PORT=7474
MAC_MINI_IP=192.168.1.50
```

### 4. Configure OpenClaw

Copy the template config and customize:
```bash
cp mac-mini/openclaw.config.json ~/.openclaw/openclaw.json
```

Edit `~/.openclaw/openclaw.json` to match your environment — update MCP server paths if you have Caddis, Epicor, or Industrial servers configured.

### 5. Start the Spatial Vision Server

```bash
node ~/.openclaw/skills/spatial-vision/scripts/server.js
```

You should see:
```
[Jarvis] Spatial Vision skill running on ws://0.0.0.0:7474
[Jarvis] Waiting for Vision Pro connections...
```

## Setup — Apple Vision Pro App

### 1. Create Xcode Project

1. Open Xcode → File → New → Project
2. Select **visionOS** → **App**
3. Product Name: `JarvisVision`
4. Interface: **SwiftUI**
5. Immersive Space Renderer: **None** (we use windowed scenes)

### 2. Add Source Files

Copy all Swift files from `JarvisVision/JarvisVision/` into your Xcode project:

```
JarvisVisionApp.swift
ContentView.swift
VoicePipeline.swift
WebSocketClient.swift
WindowManager.swift
Models/WindowPayload.swift
Windows/ChartWindowView.swift
Windows/InfoCardView.swift
Windows/WebPanelView.swift
```

### 3. Configure Capabilities

In your Xcode project settings, ensure these capabilities/entitlements:
- **Microphone Usage** — add `NSMicrophoneUsageDescription` to Info.plist
- **Speech Recognition** — add `NSSpeechRecognitionUsageDescription` to Info.plist

Add to Info.plist:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Jarvis needs microphone access to hear your voice commands.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Jarvis uses speech recognition for wake word detection.</string>
```

### 4. Set Mac Mini IP

In `WebSocketClient.swift`, update the default host IP to your Mac Mini's static LAN IP:

```swift
init(host: String = "YOUR_MAC_MINI_IP", port: Int = 7474)
```

### 5. Build and Deploy

1. Connect Vision Pro to Mac via cable or wireless debugging
2. Select your Vision Pro as the build target
3. Build and run (Cmd+R)

## Usage

1. Put on Vision Pro, launch JarvisVision
2. Wait for the blue orb to pulse (connected state)
3. Say **"Hey Jarvis"** to activate
4. Speak your command:
   - "How are the machines running today?" → Chart window
   - "Show me job 45231 cost performance" → Info card
   - "Open the Caddis dashboard" → Web panel
5. Grab and reposition windows with hand gestures
6. Say "Hey Jarvis, close everything" to dismiss all windows

## Window Types

| Type | Trigger | Render |
|------|---------|--------|
| **Chart** | Numerical/trend data | Swift Charts (bar, line, area, pie, donut, scatter) |
| **Info Card** | Status, summaries | SwiftUI + Markdown |
| **Web Panel** | Dashboards, URLs | WKWebView |

## Communication Protocol

| Direction | Format |
|-----------|--------|
| Vision Pro → Mac Mini | `{ type: "voice_input", transcript: "..." }` |
| Mac Mini → Vision Pro | `{ type: "open_window", windowType: "chart"\|"card"\|"web", windowId: "...", payload: {...} }` |
| Mac Mini → Vision Pro | `{ type: "speak_response", text: "..." }` |
| Mac Mini → Vision Pro | `{ type: "close_all" }` |
| Mac Mini → Vision Pro | `{ type: "update_window", windowId: "...", payload: {...} }` |

## Project Structure

```
jarvis/
├── JarvisVision/                        # visionOS app source files
│   └── JarvisVision/
│       ├── JarvisVisionApp.swift        # App entry, WindowGroup scenes
│       ├── ContentView.swift            # Main view, listening orb, setup
│       ├── VoicePipeline.swift          # Wake word + Whisper STT
│       ├── WebSocketClient.swift        # WebSocket client to Mac Mini
│       ├── WindowManager.swift          # Window dispatch + TTS
│       ├── Models/
│       │   └── WindowPayload.swift      # All Codable message types
│       └── Windows/
│           ├── ChartWindowView.swift    # Swift Charts renderer
│           ├── InfoCardView.swift       # Markdown info cards
│           └── WebPanelView.swift       # WKWebView wrapper
├── mac-mini/                            # Mac Mini backend
│   ├── skills/
│   │   └── spatial-vision/
│   │       ├── SKILL.md                 # OpenClaw skill manifest
│   │       └── scripts/
│   │           ├── server.js            # WebSocket server + Claude bridge
│   │           └── package.json         # Node.js dependencies
│   ├── openclaw.config.json             # OpenClaw config template
│   └── .env.example                     # Environment variables template
└── README.md
```

## Security

- All communication stays on the LAN (ws://, no cloud egress)
- API keys stored in environment variables, never in source code
- WKWebView navigation locked — no JavaScript popups or redirects
- Only custom OpenClaw skills — no community skills installed
- MCP servers run locally with their own auth

## Troubleshooting

**Vision Pro won't connect:**
- Verify both devices are on the same LAN
- Check Mac Mini firewall allows port 7474
- Verify the server is running: `curl -v ws://MAC_MINI_IP:7474`

**No audio / Whisper errors:**
- Ensure `OPENAI_API_KEY` is set in `~/.openclaw/.env`
- Check microphone permissions in Vision Pro Settings

**Claude not responding:**
- Verify `ANTHROPIC_API_KEY` is set
- Check server console for API error messages
- Ensure you haven't hit rate limits
