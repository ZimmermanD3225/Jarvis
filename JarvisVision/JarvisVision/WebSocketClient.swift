import Foundation
import Observation

@Observable
final class WebSocketClient {
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    private(set) var state: ConnectionState = .disconnected
    var onMessage: ((ServerMessage) -> Void)?
    var onAudioData: ((Data) -> Void)?  // ElevenLabs audio binary

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var serverURL: URL
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 2.0
    private var expectingAudio = false

    init(host: String = "192.168.1.50", port: Int = 7474) {
        self.serverURL = URL(string: "ws://\(host):\(port)")!
        self.session = URLSession(configuration: .default)
    }

    func connect() {
        guard state == .disconnected else { return }
        state = .connecting
        reconnectAttempts = 0
        establishConnection()
    }

    func disconnect() {
        state = .disconnected
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func send(transcript: String) {
        guard state == .connected else { return }
        let message = VoiceInputMessage(transcript: transcript)
        guard let data = try? JSONEncoder().encode(message) else { return }
        webSocketTask?.send(.data(data)) { error in
            if let error {
                print("[WebSocket] Send error: \(error.localizedDescription)")
            }
        }
    }

    func sendWindowClosed(windowId: String) {
        guard state == .connected else { return }
        let msg = ["type": "window_closed", "windowId": windowId]
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        webSocketTask?.send(.data(data)) { _ in }
    }

    private func establishConnection() {
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        state = .connected
        reconnectAttempts = 0
        startListening()
        startPingTimer()
    }

    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleRawMessage(message)
                self.startListening()

            case .failure(let error):
                print("[WebSocket] Receive error: \(error.localizedDescription)")
                self.handleDisconnect()
            }
        }
    }

    private func handleRawMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            // If we're expecting audio binary (ElevenLabs MP3), route to audio handler
            if expectingAudio {
                expectingAudio = false
                DispatchQueue.main.async { [weak self] in
                    self?.onAudioData?(data)
                }
                return
            }

            // Otherwise try to decode as JSON
            if let serverMessage = try? JSONDecoder().decode(ServerMessage.self, from: data) {
                // Check if the next message will be audio
                if case .speakResponse(let msg) = serverMessage, msg.hasAudio {
                    expectingAudio = true
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onMessage?(serverMessage)
                }
            }

        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            if let serverMessage = try? JSONDecoder().decode(ServerMessage.self, from: data) {
                if case .speakResponse(let msg) = serverMessage, msg.hasAudio {
                    expectingAudio = true
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onMessage?(serverMessage)
                }
            }

        @unknown default:
            break
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func sendPing() {
        guard state == .connected else { return }
        let ping = PingMessage()
        guard let data = try? JSONEncoder().encode(ping) else { return }
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error {
                print("[WebSocket] Ping error: \(error.localizedDescription)")
                self?.handleDisconnect()
            }
        }
    }

    private func handleDisconnect() {
        state = .disconnected
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask = nil
        expectingAudio = false
        attemptReconnect()
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("[WebSocket] Max reconnect attempts reached")
            return
        }

        reconnectAttempts += 1
        let delay = baseReconnectDelay * pow(1.5, Double(reconnectAttempts - 1))
        print("[WebSocket] Reconnecting in \(String(format: "%.1f", delay))s (attempt \(reconnectAttempts))")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.state == .disconnected else { return }
            self.state = .connecting
            self.establishConnection()
        }
    }
}
