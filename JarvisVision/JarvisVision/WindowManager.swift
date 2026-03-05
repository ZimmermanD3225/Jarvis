import SwiftUI
import AVFoundation
import Observation

@Observable
final class WindowManager {
    struct TrackedWindow: Identifiable {
        let id: String
        let windowType: WindowType
        let openedAt: Date
    }

    private(set) var openWindows: [TrackedWindow] = []
    private let synthesizer = AVSpeechSynthesizer()
    private let maxConcurrentWindows = 6
    private var openEnvironment: OpenWindowAction?
    private var dismissEnvironment: DismissWindowAction?

    var windowCount: Int { openWindows.count }

    func bindActions(open: OpenWindowAction, dismiss: DismissWindowAction) {
        self.openEnvironment = open
        self.dismissEnvironment = dismiss
    }

    func handleMessage(_ message: ServerMessage) {
        switch message {
        case .openWindow(let msg):
            openSpatialWindow(msg)

        case .speakResponse(let msg):
            speak(msg.text)

        case .closeAll:
            closeAllWindows()

        case .updateWindow(let msg):
            handleUpdateWindow(msg)

        case .pong:
            break
        }
    }

    private func openSpatialWindow(_ msg: OpenWindowMessage) {
        guard openWindows.count < maxConcurrentWindows else {
            speak("Maximum windows reached. Close some windows first.")
            return
        }

        switch msg.windowType {
        case .chart:
            guard let payload = msg.chart else { return }
            let value = ChartWindowValue(windowId: msg.windowId, payload: payload)
            openEnvironment?(value: value)

        case .card:
            guard let payload = msg.card else { return }
            let value = InfoCardWindowValue(windowId: msg.windowId, payload: payload)
            openEnvironment?(value: value)

        case .web:
            guard let payload = msg.web else { return }
            let value = WebPanelWindowValue(windowId: msg.windowId, payload: payload)
            openEnvironment?(value: value)
        }

        openWindows.append(TrackedWindow(
            id: msg.windowId,
            windowType: msg.windowType,
            openedAt: Date()
        ))
    }

    func closeWindow(id: String) {
        openWindows.removeAll { $0.id == id }
    }

    private func closeAllWindows() {
        openWindows.removeAll()
        dismissEnvironment?(id: "Chart")
        dismissEnvironment?(id: "Info Card")
        dismissEnvironment?(id: "Web Panel")
    }

    private func handleUpdateWindow(_ msg: UpdateWindowMessage) {
        // Window updates are handled by re-opening with new data
        // Individual views can observe changes through their bindings
        print("[WindowManager] Update request for window: \(msg.windowId)")
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }
}
