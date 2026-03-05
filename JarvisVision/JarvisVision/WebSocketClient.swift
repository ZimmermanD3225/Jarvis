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

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var serverURL: URL
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 2.0

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
        let wsMessage = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(wsMessage) { error in
            if let error {
                print("[WebSocket] Send error: \(error.localizedDescription)")
            }
        }
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
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }

        do {
            let serverMessage = try JSONDecoder().decode(ServerMessage.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.onMessage?(serverMessage)
            }
        } catch {
            print("[WebSocket] Decode error: \(error.localizedDescription)")
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
