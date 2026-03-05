import Foundation

// MARK: - Inbound Messages (Mac Mini → Vision Pro)

enum ServerMessage: Decodable {
    case openWindow(OpenWindowMessage)
    case speakResponse(SpeakResponseMessage)
    case closeAll
    case updateWindow(UpdateWindowMessage)
    case pong

    enum CodingKeys: String, CodingKey {
        case type, windowType, windowId, payload, text, hasAudio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "open_window":
            let windowType = try container.decode(WindowType.self, forKey: .windowType)
            let windowId = try container.decode(String.self, forKey: .windowId)

            switch windowType {
            case .chart:
                let payload = try container.decode(ChartPayload.self, forKey: .payload)
                self = .openWindow(OpenWindowMessage(windowType: .chart, windowId: windowId, chart: payload, card: nil, web: nil))
            case .card:
                let payload = try container.decode(InfoCardPayload.self, forKey: .payload)
                self = .openWindow(OpenWindowMessage(windowType: .card, windowId: windowId, chart: nil, card: payload, web: nil))
            case .web:
                let payload = try container.decode(WebPanelPayload.self, forKey: .payload)
                self = .openWindow(OpenWindowMessage(windowType: .web, windowId: windowId, chart: nil, card: nil, web: payload))
            }

        case "speak_response":
            let text = try container.decode(String.self, forKey: .text)
            let hasAudio = (try? container.decode(Bool.self, forKey: .hasAudio)) ?? false
            self = .speakResponse(SpeakResponseMessage(text: text, hasAudio: hasAudio))

        case "close_all":
            self = .closeAll

        case "update_window":
            let windowId = try container.decode(String.self, forKey: .windowId)
            let payload = try container.decode(GenericPayload.self, forKey: .payload)
            self = .updateWindow(UpdateWindowMessage(windowId: windowId, payload: payload))

        case "pong":
            self = .pong

        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }
}

// MARK: - Window Types

enum WindowType: String, Codable, Hashable {
    case chart
    case card
    case web
}

// MARK: - Open Window Message

struct OpenWindowMessage: Identifiable {
    let id = UUID()
    let windowType: WindowType
    let windowId: String
    let chart: ChartPayload?
    let card: InfoCardPayload?
    let web: WebPanelPayload?
}

// MARK: - Speak Response

struct SpeakResponseMessage {
    let text: String
    let hasAudio: Bool
}

// MARK: - Update Window

struct UpdateWindowMessage {
    let windowId: String
    let payload: GenericPayload
}

// MARK: - Chart Payload

struct ChartPayload: Codable, Hashable, Identifiable {
    let id = UUID()
    let title: String
    let chartType: ChartType
    let data: [ChartDataPoint]
    let xLabel: String?
    let yLabel: String?
    let refreshUrl: String?
    let intervalSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case title, chartType, data, xLabel, yLabel, refreshUrl, intervalSeconds
    }
}

enum ChartType: String, Codable, Hashable {
    case bar, line, area, pie, donut, scatter
}

struct ChartDataPoint: Codable, Hashable, Identifiable {
    let id = UUID()
    let label: String
    let value: Double

    enum CodingKeys: String, CodingKey {
        case label, value
    }
}

// MARK: - Info Card Payload

struct InfoCardPayload: Codable, Hashable, Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let statusBadge: StatusBadge?

    enum CodingKeys: String, CodingKey {
        case title, content, statusBadge
    }
}

enum StatusBadge: String, Codable, Hashable {
    case green, yellow, red, none
}

// MARK: - Web Panel Payload

struct WebPanelPayload: Codable, Hashable, Identifiable {
    let id = UUID()
    let url: String?
    let html: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case url, html, title
    }
}

// MARK: - Generic Payload (for updates)

struct GenericPayload: Codable {
    let values: [String: AnyCodableValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: AnyCodableValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

enum AnyCodableValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if container.decodeNil() { self = .null }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Outbound Messages (Vision Pro → Mac Mini)

struct VoiceInputMessage: Encodable {
    let type = "voice_input"
    let transcript: String
}

struct PingMessage: Encodable {
    let type = "ping"
}

// MARK: - Window Scene Value Types (for openWindow)

struct ChartWindowValue: Codable, Hashable {
    let windowId: String
    let payload: ChartPayload
}

struct InfoCardWindowValue: Codable, Hashable {
    let windowId: String
    let payload: InfoCardPayload
}

struct WebPanelWindowValue: Codable, Hashable {
    let windowId: String
    let payload: WebPanelPayload
}
