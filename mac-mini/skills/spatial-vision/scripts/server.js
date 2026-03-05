import { WebSocketServer, WebSocket } from "ws";
import Anthropic from "@anthropic-ai/sdk";

const PORT = parseInt(process.env.JARVIS_WS_PORT || "7474", 10);
const HEARTBEAT_INTERVAL = 15_000;
const MODEL = "claude-sonnet-4-5-20250514";

const anthropic = new Anthropic();

const SYSTEM_PROMPT = `You are Jarvis, a spatial AI assistant running on Apple Vision Pro.
You have tools to open floating windows in the user's field of view.
Always prefer visual responses when data is involved:
 - Use open_chart_window for any numerical/trend data
 - Use open_info_card for status, summaries, and structured info
 - Use open_web_panel for dashboards or URLs
 - Use speak_response only for conversational replies with no data
Be concise in speech. Let the windows do the heavy lifting.
You have access to manufacturing data via Caddis, Epicor, and Industrial tools.
The user is Dave, IT Director at LeClaire Manufacturing, Bettendorf Iowa.
When multiple pieces of information are requested, open multiple windows simultaneously.
Always acknowledge commands with a brief spoken response in addition to any windows.`;

const TOOLS = [
  {
    name: "open_chart_window",
    description:
      "Opens a floating chart panel in the user's Vision Pro field of view. Use for any numerical, trend, or comparative data.",
    input_schema: {
      type: "object",
      required: ["title", "chartType", "data"],
      properties: {
        title: { type: "string", description: "Chart title displayed at top" },
        chartType: {
          type: "string",
          enum: ["bar", "line", "area", "pie", "donut", "scatter"],
          description: "Type of chart to render",
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
          description: "Array of data points with label and numeric value",
        },
        xLabel: { type: "string", description: "X-axis label" },
        yLabel: { type: "string", description: "Y-axis label" },
        refreshUrl: {
          type: "string",
          description: "Optional URL to poll for updated data",
        },
        intervalSeconds: {
          type: "number",
          description: "Refresh interval in seconds (requires refreshUrl)",
        },
      },
    },
  },
  {
    name: "open_info_card",
    description:
      "Opens a floating info card with rich markdown content. Use for status reports, summaries, structured information, and text-heavy responses.",
    input_schema: {
      type: "object",
      required: ["title", "content"],
      properties: {
        title: { type: "string", description: "Card title" },
        content: {
          type: "string",
          description:
            "Markdown-formatted content. Supports headers, bold, italic, code, tables, and lists.",
        },
        statusBadge: {
          type: "string",
          enum: ["green", "yellow", "red", "none"],
          description:
            "Optional status indicator badge in the top-right corner",
        },
      },
    },
  },
  {
    name: "open_web_panel",
    description:
      "Opens a floating web browser panel. Provide either a URL to load a remote page or raw HTML to render directly.",
    input_schema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to load in the web panel" },
        html: {
          type: "string",
          description: "Raw HTML string to render directly",
        },
        title: { type: "string", description: "Panel title bar text" },
      },
    },
  },
  {
    name: "close_all_windows",
    description:
      "Dismisses all currently open spatial windows in Vision Pro.",
    input_schema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "speak_response",
    description:
      "Speaks text through Vision Pro's TTS without opening any window. Use for brief conversational replies, confirmations, and acknowledgments.",
    input_schema: {
      type: "object",
      required: ["text"],
      properties: {
        text: {
          type: "string",
          description: "Text to speak aloud",
        },
      },
    },
  },
  {
    name: "update_window",
    description:
      "Updates the content of an existing open window by its ID. Use to refresh data without opening a new window.",
    input_schema: {
      type: "object",
      required: ["windowId", "payload"],
      properties: {
        windowId: {
          type: "string",
          description: "The ID of the window to update",
        },
        payload: {
          type: "object",
          description: "New payload data to replace the window content",
        },
      },
    },
  },
];

const conversationHistory = [];
const MAX_HISTORY = 50;

function trimHistory() {
  while (conversationHistory.length > MAX_HISTORY) {
    conversationHistory.shift();
  }
}

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

function generateWindowId() {
  return `win_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

async function handleVoiceInput(transcript) {
  console.log(`[Jarvis] Received: "${transcript}"`);

  conversationHistory.push({ role: "user", content: transcript });
  trimHistory();

  try {
    let response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      tools: TOOLS,
      messages: [...conversationHistory],
    });

    const toolResults = [];

    while (response.stop_reason === "tool_use") {
      const assistantContent = response.content;
      conversationHistory.push({ role: "assistant", content: assistantContent });

      const toolUseBlocks = assistantContent.filter(
        (block) => block.type === "tool_use"
      );

      for (const toolUse of toolUseBlocks) {
        const { id, name, input } = toolUse;
        console.log(`[Jarvis] Tool call: ${name}`, JSON.stringify(input));

        const windowId = generateWindowId();
        let delivered = false;

        switch (name) {
          case "open_chart_window":
            broadcast({
              type: "open_window",
              windowType: "chart",
              windowId,
              payload: input,
            });
            delivered = true;
            break;

          case "open_info_card":
            broadcast({
              type: "open_window",
              windowType: "card",
              windowId,
              payload: input,
            });
            delivered = true;
            break;

          case "open_web_panel":
            broadcast({
              type: "open_window",
              windowType: "web",
              windowId,
              payload: input,
            });
            delivered = true;
            break;

          case "close_all_windows":
            broadcast({ type: "close_all" });
            delivered = true;
            break;

          case "speak_response":
            broadcast({
              type: "speak_response",
              text: input.text,
            });
            delivered = true;
            break;

          case "update_window":
            broadcast({
              type: "update_window",
              windowId: input.windowId,
              payload: input.payload,
            });
            delivered = true;
            break;

          default:
            console.warn(`[Jarvis] Unknown tool: ${name}`);
        }

        toolResults.push({
          type: "tool_result",
          tool_use_id: id,
          content: delivered
            ? `${name} delivered successfully. windowId: ${windowId}`
            : `Unknown tool: ${name}`,
        });
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

    const textBlocks = finalContent.filter((block) => block.type === "text");
    if (textBlocks.length > 0) {
      const text = textBlocks.map((b) => b.text).join("\n");
      if (text.trim()) {
        broadcast({ type: "speak_response", text: text.trim() });
      }
    }
  } catch (err) {
    console.error("[Jarvis] Claude API error:", err.message);
    broadcast({
      type: "speak_response",
      text: "I encountered an error processing your request. Please try again.",
    });
  }
}

wss.on("connection", (ws, req) => {
  const clientAddr = req.socket.remoteAddress;
  console.log(`[Jarvis] Vision Pro connected from ${clientAddr}`);
  clients.add(ws);

  ws.isAlive = true;
  ws.on("pong", () => {
    ws.isAlive = true;
  });

  ws.on("message", (raw) => {
    try {
      const message = JSON.parse(raw.toString());

      switch (message.type) {
        case "voice_input":
          if (message.transcript?.trim()) {
            handleVoiceInput(message.transcript.trim());
          }
          break;

        case "ping":
          ws.send(JSON.stringify({ type: "pong" }));
          break;

        default:
          console.warn(`[Jarvis] Unknown message type: ${message.type}`);
      }
    } catch (err) {
      console.error("[Jarvis] Failed to parse message:", err.message);
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

  ws.send(
    JSON.stringify({
      type: "speak_response",
      text: "Jarvis online. How can I help you, Dave?",
    })
  );
});

const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate();
      clients.delete(ws);
      return;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_INTERVAL);

wss.on("close", () => {
  clearInterval(heartbeat);
});

console.log(`[Jarvis] Spatial Vision skill running on ws://0.0.0.0:${PORT}`);
console.log(`[Jarvis] Waiting for Vision Pro connections...`);
