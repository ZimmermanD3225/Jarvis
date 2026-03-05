import { WebSocketServer, WebSocket } from "ws";
import Anthropic from "@anthropic-ai/sdk";
import https from "https";

const PORT = parseInt(process.env.JARVIS_WS_PORT || "7474", 10);
const HEARTBEAT_INTERVAL = 15_000;
const MODEL = "claude-sonnet-4-5-20250514";

// ElevenLabs config
const ELEVENLABS_API_KEY = process.env.ELEVENLABS_API_KEY || "";
const ELEVENLABS_VOICE_ID = process.env.ELEVENLABS_VOICE_ID || "pNInz6obpgDQGcFmaJgB"; // "Adam" — deep, calm
const ELEVENLABS_MODEL = "eleven_flash_v2_5"; // Lowest latency
const USE_ELEVENLABS = !!ELEVENLABS_API_KEY;

const anthropic = new Anthropic();

// ═══════════════════════════════════════════════════════════════════
// SYSTEM PROMPT — The soul of Jarvis
// ═══════════════════════════════════════════════════════════════════

const SYSTEM_PROMPT = `You are Jarvis — a spatial AI assistant projected through Apple Vision Pro.

PERSONALITY:
- You speak with calm authority and dry wit. Think Paul Bettany's Jarvis: measured, slightly British, never flustered.
- You address the user as "Dave" or occasionally "sir." Never "user."
- Be concise. A spoken response should rarely exceed two sentences. Let the floating windows do the heavy lifting.
- When you're uncertain, say so directly: "I don't have that data at hand, Dave."
- You may add brief, understated observations: "That scrap rate is rather alarming."
- Never be sycophantic. Never say "Great question!" or "I'd be happy to help."
- If Dave is thinking out loud, respond only if there's something genuinely useful to add. Sometimes silence is the right answer — but if you do respond, make it count.

SPATIAL DISPLAY RULES:
- You have tools to open floating holographic windows in Dave's field of view.
- ALWAYS prefer visual responses when data is involved:
  • open_chart_window — for any numerical, trend, or comparative data
  • open_info_card — for status reports, structured information, summaries
  • open_web_panel — for dashboards, web tools, or live embeds
- Use speak_response for brief conversational replies, confirmations, or when no visual is needed.
- When showing data, ALWAYS pair it with a brief spoken acknowledgment: open the window AND speak.
- When multiple pieces of information are requested, open multiple windows simultaneously.
- Keep info card markdown clean and scannable. Use headers, bold for key values, and tables for comparisons.

CONTEXT:
- Dave is the IT Director at LeClaire Manufacturing in Bettendorf, Iowa.
- He has access to manufacturing data via Caddis CMMS (equipment, maintenance), Epicor/Jobcost (cost performance, scrap data, labor), and Industrial Server (PLC/SCADA, OEE metrics).
- If asked about data you don't currently have tool access for, say so and suggest what MCP connection would provide it.

THINKING OUT LOUD:
- Dave often thinks out loud while wearing the headset. Not everything he says is a direct command.
- If he says something like "I wonder if the lathe is still down..." — that IS a question. Look it up and show him.
- If he says something like "OK let me think about this for a second..." — that's NOT a command. Respond briefly: "Take your time, Dave." or simply stay quiet.
- Use judgment. Err on the side of being helpful — if you can answer it, answer it.`;

// ═══════════════════════════════════════════════════════════════════
// TOOL DEFINITIONS
// ═══════════════════════════════════════════════════════════════════

const TOOLS = [
  {
    name: "open_chart_window",
    description:
      "Opens a floating holographic chart in Vision Pro. Use for numerical data, trends, comparisons, or any data that benefits from visualization.",
    input_schema: {
      type: "object",
      required: ["title", "chartType", "data"],
      properties: {
        title: { type: "string", description: "Chart title" },
        chartType: {
          type: "string",
          enum: ["bar", "line", "area", "pie", "donut", "scatter"],
        },
        data: {
          type: "array",
          items: {
            type: "object",
            required: ["label", "value"],
            properties: {
              label: { type: "string" },
              value: { type: "number" },
            },
          },
        },
        xLabel: { type: "string" },
        yLabel: { type: "string" },
        refreshUrl: { type: "string", description: "URL to poll for live data updates" },
        intervalSeconds: { type: "number", description: "Auto-refresh interval" },
      },
    },
  },
  {
    name: "open_info_card",
    description:
      "Opens a floating info card with rich markdown. Use for status reports, summaries, job details, structured text, or any information that benefits from a readable card layout.",
    input_schema: {
      type: "object",
      required: ["title", "content"],
      properties: {
        title: { type: "string" },
        content: {
          type: "string",
          description:
            "Markdown content. Use ## headers to organize sections, **bold** for key values, tables for comparisons, and - lists for items.",
        },
        statusBadge: {
          type: "string",
          enum: ["green", "yellow", "red", "none"],
          description: "Visual status indicator: green=good, yellow=warning, red=critical",
        },
      },
    },
  },
  {
    name: "open_web_panel",
    description:
      "Opens a floating web panel. Use for dashboards (Grafana, Caddis UI), internal web tools, or rich HTML content.",
    input_schema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to load" },
        html: { type: "string", description: "Raw HTML to render" },
        title: { type: "string" },
      },
    },
  },
  {
    name: "close_all_windows",
    description: "Dismisses all open spatial windows.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "speak_response",
    description:
      "Speaks text through Vision Pro without opening a window. Keep it brief — one or two sentences max. Use for acknowledgments, conversational replies, and thinking-out-loud responses.",
    input_schema: {
      type: "object",
      required: ["text"],
      properties: {
        text: { type: "string", description: "Text to speak aloud" },
      },
    },
  },
  {
    name: "update_window",
    description: "Updates an existing window's content by ID.",
    input_schema: {
      type: "object",
      required: ["windowId", "payload"],
      properties: {
        windowId: { type: "string" },
        payload: { type: "object", description: "New payload data" },
      },
    },
  },
];

// ═══════════════════════════════════════════════════════════════════
// CONVERSATION STATE
// ═══════════════════════════════════════════════════════════════════

const conversationHistory = [];
const MAX_HISTORY = 60;
const activeWindows = new Map(); // windowId -> { type, title, openedAt }

function trimHistory() {
  while (conversationHistory.length > MAX_HISTORY) {
    conversationHistory.shift();
  }
}

function windowContextString() {
  if (activeWindows.size === 0) return "No windows currently open.";
  const lines = [...activeWindows.entries()].map(
    ([id, w]) => `  - [${w.type}] "${w.title}" (id: ${id})`
  );
  return `Currently open windows:\n${lines.join("\n")}`;
}

// ═══════════════════════════════════════════════════════════════════
// ELEVENLABS TTS
// ═══════════════════════════════════════════════════════════════════

async function synthesizeSpeech(text) {
  if (!USE_ELEVENLABS) return null;

  const postData = JSON.stringify({
    text,
    model_id: ELEVENLABS_MODEL,
    voice_settings: {
      stability: 0.65,
      similarity_boost: 0.8,
      style: 0.15,
      use_speaker_boost: true,
    },
  });

  return new Promise((resolve) => {
    const req = https.request(
      {
        hostname: "api.elevenlabs.io",
        path: `/v1/text-to-speech/${ELEVENLABS_VOICE_ID}`,
        method: "POST",
        headers: {
          "xi-api-key": ELEVENLABS_API_KEY,
          "Content-Type": "application/json",
          Accept: "audio/mpeg",
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          if (res.statusCode === 200) {
            resolve(Buffer.concat(chunks));
          } else {
            console.error(`[ElevenLabs] HTTP ${res.statusCode}`);
            resolve(null);
          }
        });
      }
    );
    req.on("error", (err) => {
      console.error("[ElevenLabs] Request error:", err.message);
      resolve(null);
    });
    req.write(postData);
    req.end();
  });
}

async function speakToClients(text) {
  if (USE_ELEVENLABS) {
    const audioBuffer = await synthesizeSpeech(text);
    if (audioBuffer) {
      broadcast({ type: "speak_response", text, hasAudio: true });
      broadcastBinary(audioBuffer);
      return;
    }
  }
  // Fallback: device TTS
  broadcast({ type: "speak_response", text });
}

// ═══════════════════════════════════════════════════════════════════
// WEBSOCKET SERVER
// ═══════════════════════════════════════════════════════════════════

const wss = new WebSocketServer({ port: PORT });
const clients = new Set();

function broadcast(message) {
  const data = JSON.stringify(message);
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  }
}

function broadcastBinary(data) {
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  }
}

function generateWindowId() {
  return `win_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

// ═══════════════════════════════════════════════════════════════════
// CLAUDE INTERACTION
// ═══════════════════════════════════════════════════════════════════

let isProcessing = false;
const pendingTranscripts = [];

async function handleVoiceInput(transcript) {
  if (isProcessing) {
    pendingTranscripts.push(transcript);
    console.log(`[Jarvis] Queued (processing): "${transcript}"`);
    return;
  }

  isProcessing = true;
  console.log(`[Jarvis] Received: "${transcript}"`);

  const contextualMessage = `${transcript}\n\n[System context: ${windowContextString()}]`;
  conversationHistory.push({ role: "user", content: contextualMessage });
  trimHistory();

  try {
    let response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      tools: TOOLS,
      messages: [...conversationHistory],
    });

    while (response.stop_reason === "tool_use") {
      const assistantContent = response.content;
      conversationHistory.push({ role: "assistant", content: assistantContent });

      const toolUseBlocks = assistantContent.filter((b) => b.type === "tool_use");
      const toolResults = [];

      for (const toolUse of toolUseBlocks) {
        const { id, name, input } = toolUse;
        console.log(`[Jarvis] Tool: ${name}`, JSON.stringify(input).slice(0, 200));

        const windowId = generateWindowId();
        let result = "";

        switch (name) {
          case "open_chart_window": {
            broadcast({ type: "open_window", windowType: "chart", windowId, payload: input });
            activeWindows.set(windowId, { type: "chart", title: input.title, openedAt: new Date() });
            result = `Chart window opened. windowId: ${windowId}`;
            break;
          }
          case "open_info_card": {
            broadcast({ type: "open_window", windowType: "card", windowId, payload: input });
            activeWindows.set(windowId, { type: "card", title: input.title, openedAt: new Date() });
            result = `Info card opened. windowId: ${windowId}`;
            break;
          }
          case "open_web_panel": {
            broadcast({ type: "open_window", windowType: "web", windowId, payload: input });
            activeWindows.set(windowId, { type: "web", title: input.title || input.url || "Web Panel", openedAt: new Date() });
            result = `Web panel opened. windowId: ${windowId}`;
            break;
          }
          case "close_all_windows": {
            broadcast({ type: "close_all" });
            activeWindows.clear();
            result = "All windows dismissed.";
            break;
          }
          case "speak_response": {
            await speakToClients(input.text);
            result = "Spoken.";
            break;
          }
          case "update_window": {
            broadcast({ type: "update_window", windowId: input.windowId, payload: input.payload });
            result = `Window ${input.windowId} updated.`;
            break;
          }
          default:
            result = `Unknown tool: ${name}`;
        }

        toolResults.push({ type: "tool_result", tool_use_id: id, content: result });
      }

      conversationHistory.push({ role: "user", content: toolResults });

      response = await anthropic.messages.create({
        model: MODEL,
        max_tokens: 4096,
        system: SYSTEM_PROMPT,
        tools: TOOLS,
        messages: [...conversationHistory],
      });
    }

    const finalContent = response.content;
    conversationHistory.push({ role: "assistant", content: finalContent });
    trimHistory();

    const textBlocks = finalContent.filter((b) => b.type === "text");
    if (textBlocks.length > 0) {
      const text = textBlocks.map((b) => b.text).join("\n").trim();
      if (text) {
        await speakToClients(text);
      }
    }
  } catch (err) {
    console.error("[Jarvis] Claude API error:", err.message);
    await speakToClients("I've encountered a processing error, Dave. Give me a moment.");
  }

  isProcessing = false;

  if (pendingTranscripts.length > 0) {
    const next = pendingTranscripts.shift();
    handleVoiceInput(next);
  }
}

// ═══════════════════════════════════════════════════════════════════
// CONNECTION HANDLING
// ═══════════════════════════════════════════════════════════════════

wss.on("connection", (ws, req) => {
  const clientAddr = req.socket.remoteAddress;
  console.log(`[Jarvis] Vision Pro connected from ${clientAddr}`);
  clients.add(ws);

  ws.isAlive = true;
  ws.on("pong", () => { ws.isAlive = true; });

  ws.on("message", async (raw) => {
    if (Buffer.isBuffer(raw) && raw[0] !== 0x7b) return;

    try {
      const message = JSON.parse(raw.toString());

      switch (message.type) {
        case "voice_input":
          if (message.transcript?.trim()) {
            handleVoiceInput(message.transcript.trim());
          }
          break;
        case "window_closed":
          if (message.windowId) activeWindows.delete(message.windowId);
          break;
        case "ping":
          ws.send(JSON.stringify({ type: "pong" }));
          break;
        default:
          console.warn(`[Jarvis] Unknown message type: ${message.type}`);
      }
    } catch (err) {
      console.error("[Jarvis] Parse error:", err.message);
    }
  });

  ws.on("close", () => {
    console.log(`[Jarvis] Vision Pro disconnected: ${clientAddr}`);
    clients.delete(ws);
  });

  ws.on("error", (err) => {
    console.error(`[Jarvis] WebSocket error (${clientAddr}):`, err.message);
    clients.delete(ws);
  });

  const welcomeText = "Jarvis online. All systems nominal, Dave.";
  speakToClients(welcomeText);
});

const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate();
      clients.delete(ws);
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_INTERVAL);

wss.on("close", () => { clearInterval(heartbeat); });

// ═══════════════════════════════════════════════════════════════════
// STARTUP
// ═══════════════════════════════════════════════════════════════════

console.log("");
console.log("  ╔═══════════════════════════════════════╗");
console.log("  ║        J.A.R.V.I.S. v1.0              ║");
console.log("  ║   Spatial Vision Skill — Online        ║");
console.log("  ╠═══════════════════════════════════════╣");
console.log(`  ║   WebSocket:  ws://0.0.0.0:${PORT}       ║`);
console.log(`  ║   Model:      ${MODEL}  ║`);
console.log(`  ║   TTS:        ${USE_ELEVENLABS ? "ElevenLabs" : "Device (AVSpeechSynthesizer)"}  ║`);
console.log("  ╚═══════════════════════════════════════╝");
console.log("");
console.log("  Awaiting Vision Pro connection...");
console.log("");
