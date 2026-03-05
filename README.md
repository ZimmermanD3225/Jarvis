# Project Jarvis

Spatial AI Assistant — Apple Vision Pro + OpenClaw + Mac Mini

Jarvis is a personal spatial AI assistant that combines Apple Vision Pro's mixed-reality display with OpenClaw's agent framework running on a Mac Mini. Speak a command, and floating holographic windows materialize in your field of view — charts, info cards, and web panels — all orchestrated by Claude as the reasoning engine, with ElevenLabs providing premium voice synthesis.

## Architecture

```
┌─────────────────────────────────┐      ┌──────────────────────────────────────┐
│       APPLE VISION PRO           │      │           MAC MINI M4 PRO            │
│                                 │      │                                      │
│  "Hey Jarvis" (wake word)       │      │  OpenClaw + Spatial Vision Skill     │
│    └─ SFSpeechRecognizer        │      │    ├── Claude API (tool router)      │
│    └─ Whisper STT (command)     │      │    ├── ElevenLabs TTS (voice)        │
│    └─ WebSocket ────────────────┼─────→│    ├── Caddis CMMS MCP               │
│                                 │      │    ├── Epicor / Jobcost MCP          │
│  Arc Reactor Orb (HUD)         │      │    └── Industrial Server MCP         │
│  Holographic Windows ◄──────────┼──────┤                                      │
│    ├── Chart Window             │      │  WebSocket server on port 7474       │
│    ├── Info Card Window         │      │                                      │
│    └── Web Panel Window         │      │  ElevenLabs audio → binary WS        │
└─────────────────────────────────┘      └──────────────────────────────────────┘
              LAN (Wi-Fi 6 / Ethernet)
```

## Features

- **"Hey Jarvis" wake word** — on-device SFSpeechRecognizer, always listening
- **Conversational mode** — after Jarvis responds, stays listening for 30s without requiring wake word (thinking out loud)
- **Arc reactor orb** — concentric rotating rings, energy core, breathing pulse animation
- **Boot sequence** — dramatic system initialization on launch
- **Holographic windows** — rotating border glow, scan line effects, frosted glass
- **6 chart types** — bar, line, area, pie, donut, scatter with animated entry and data labels
- **Markdown info cards** — full block-level rendering (headers, tables, lists) with pulsing status badges
- **Web panels** — WKWebView with Iron Man-styled HTML injection and progress bar
- **ElevenLabs TTS** — premium voice synthesis with sub-100ms latency (falls back to device TTS)
- **Audio waveform** — real-time visualization of mic input during listening
- **HUD elements** — time, connection status, panel count, pipeline state

## Prerequisites

- **Mac Mini M4 Pro** (or any Mac) with Node.js 22+
- **Apple Vision Pro** with Developer Mode enabled
- **Xcode 15+** (for building the visionOS app)
- **Anthropic API key** ([console.anthropic.com](https://console.anthropic.com))
- **OpenAI API key** ([platform.openai.com](https://platform.openai.com)) — for Whisper STT
- **ElevenLabs API key** ([elevenlabs.io](https://elevenlabs.io)) — optional, for premium voice

## Setup — Mac Mini Backend

### 1. Install OpenClaw

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

### 2. Install the Spatial Vision Skill

```bash
cp -r mac-mini/skills/spatial-vision ~/.openclaw/skills/
cd ~/.openclaw/skills/spatial-vision/scripts
npm install
```

### 3. Configure Environment

```bash
cp mac-mini/.env.example ~/.openclaw/.env
nano ~/.openclaw/.env
```

Required:
```
ANTHROPIC_API_KEY=sk-ant-your-key-here
OPENAI_API_KEY=sk-your-key-here
JARVIS_WS_PORT=7474
MAC_MINI_IP=192.168.1.50
```

Optional (premium voice):
```
ELEVENLABS_API_KEY=your-key-here
ELEVENLABS_VOICE_ID=pNInz6obpgDQGcFmaJgB
```

### 4. Configure OpenClaw

```bash
cp mac-mini/openclaw.config.json ~/.openclaw/openclaw.json
```

Edit to match your environment — update MCP server paths for Caddis, Epicor, etc.

### 5. Start the Server

```bash
node ~/.openclaw/skills/spatial-vision/scripts/server.js
```

You should see:
```
  ╔═══════════════════════════════════════╗
  ║        J.A.R.V.I.S. v1.0              ║
  ║   Spatial Vision Skill — Online        ║
  ╠═══════════════════════════════════════╣
  ║   WebSocket:  ws://0.0.0.0:7474       ║
  ║   TTS:        ElevenLabs               ║
  ╚═══════════════════════════════════════╝

  Awaiting Vision Pro connection...
```

## Setup — Apple Vision Pro App

### 1. Create Xcode Project

1. Open Xcode -> File -> New -> Project
2. Select **visionOS** -> **App**
3. Product Name: `JarvisVision`
4. Interface: **SwiftUI**
5. Immersive Space Renderer: **None** (we use windowed scenes)

### 2. Add Source Files

Copy all Swift files from `JarvisVision/JarvisVision/` into your Xcode project:

```
JarvisVisionApp.swift
ContentView.swift
HolographicStyle.swift          <-- NEW: shared visual effects
VoicePipeline.swift
WebSocketClient.swift
WindowManager.swift
Models/WindowPayload.swift
Windows/ChartWindowView.swift
Windows/InfoCardView.swift
Windows/WebPanelView.swift
```

### 3. Configure Capabilities

Add to Info.plist:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Jarvis needs microphone access to hear your voice commands.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Jarvis uses speech recognition for wake word detection.</string>
```

### 4. Set Mac Mini IP

In `WebSocketClient.swift`, update the default host:

```swift
init(host: String = "YOUR_MAC_MINI_IP", port: Int = 7474)
```

### 5. Build and Deploy

1. Connect Vision Pro to Mac
2. Select Vision Pro as build target
3. Build and run (Cmd+R)

## Usage

1. Launch JarvisVision — watch the boot sequence initialize
2. The arc reactor orb pulses blue when connected
3. Say **"Hey Jarvis"** to activate
4. Speak naturally:
   - "How are the machines running today?" -> holographic chart
   - "Show me job 45231 cost performance" -> info card with status badge
   - "Open the Caddis dashboard" -> embedded web panel
   - "I wonder if the lathe is still down..." -> Jarvis proactively looks it up
5. After Jarvis responds, **keep talking** — conversational mode stays active for 30s
6. Grab and reposition windows with hand gestures
7. "Hey Jarvis, close everything" to dismiss all windows

## Voice Interaction

| Mode | How it works |
|------|-------------|
| **Wake word** | "Hey Jarvis" detected on-device via SFSpeechRecognizer |
| **Command** | After wake word, speech captured and sent to Whisper API |
| **Conversational** | After Jarvis responds, 30s window — no wake word needed |
| **Thinking out loud** | Jarvis uses judgment — answers questions, ignores non-commands |

## Window Types

| Type | Trigger | Render |
|------|---------|--------|
| **Chart** | Numerical/trend data | Swift Charts — bar, line, area, pie, donut, scatter |
| **Info Card** | Status, summaries | SwiftUI + full Markdown (headers, tables, lists) |
| **Web Panel** | Dashboards, URLs | WKWebView with Iron Man-styled CSS |

## Project Structure

```
jarvis/
├── JarvisVision/                        # visionOS app source files
│   └── JarvisVision/
│       ├── JarvisVisionApp.swift        # App entry, 4 WindowGroup scenes
│       ├── ContentView.swift            # Arc reactor orb, HUD, boot sequence
│       ├── HolographicStyle.swift       # Shared: borders, scan lines, palette
│       ├── VoicePipeline.swift          # Wake word + Whisper + conversational mode
│       ├── WebSocketClient.swift        # WebSocket + ElevenLabs audio binary
│       ├── WindowManager.swift          # Window dispatch + TTS + audio playback
│       ├── Models/
│       │   └── WindowPayload.swift      # All Codable message types
│       └── Windows/
│           ├── ChartWindowView.swift    # Swift Charts with holo effects
│           ├── InfoCardView.swift       # Markdown cards with status badges
│           └── WebPanelView.swift       # WKWebView with progress bar
├── mac-mini/                            # Mac Mini backend
│   ├── skills/
│   │   └── spatial-vision/
│   │       ├── SKILL.md                 # OpenClaw skill manifest
│   │       └── scripts/
│   │           ├── server.js            # Claude bridge + ElevenLabs TTS
│   │           └── package.json         # Node.js dependencies
│   ├── openclaw.config.json             # OpenClaw config template
│   └── .env.example                     # Environment variables template
└── README.md
```

## Security

- All communication stays on the LAN (ws://, no cloud egress for factory data)
- API keys stored in environment variables, never in source code
- WKWebView navigation locked — no JavaScript popups or redirects
- Only custom OpenClaw skills — no community skills installed
- MCP servers run locally with their own auth
- ElevenLabs audio synthesized server-side, streamed as binary over WebSocket

## Troubleshooting

**Vision Pro won't connect:**
- Verify both devices are on the same LAN
- Check Mac Mini firewall allows port 7474
- Verify the server is running: look for the startup banner in terminal

**No audio / Whisper errors:**
- Ensure `OPENAI_API_KEY` is set in `~/.openclaw/.env`
- Check microphone permissions in Vision Pro Settings -> Privacy

**ElevenLabs not working:**
- Verify `ELEVENLABS_API_KEY` is set — if empty, falls back to device TTS
- Check voice ID is valid at [elevenlabs.io/voice-library](https://elevenlabs.io/voice-library)
- Server console will log `[ElevenLabs] HTTP 4xx` errors

**Claude not responding:**
- Verify `ANTHROPIC_API_KEY` is set
- Check server console for API error messages
- Ensure you haven't hit rate limits
