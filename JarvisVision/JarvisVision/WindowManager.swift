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
    private(set) var isSpeaking = false
    private(set) var lastSpokenText: String = ""
    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?
    private var audioPlayer: AVAudioPlayer?
    private let maxConcurrentWindows = 6
    private var openEnvironment: OpenWindowAction?
    private var dismissEnvironment: DismissWindowAction?
    private var pendingAudioSpeakText: String?

    var windowCount: Int { openWindows.count }

    init() {
        speechDelegate = SpeechDelegate(manager: self)
        synthesizer.delegate = speechDelegate

        // Configure audio session for playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func bindActions(open: OpenWindowAction, dismiss: DismissWindowAction) {
        self.openEnvironment = open
        self.dismissEnvironment = dismiss
    }

    func handleMessage(_ message: ServerMessage) {
        switch message {
        case .openWindow(let msg):
            openSpatialWindow(msg)

        case .speakResponse(let msg):
            if msg.hasAudio {
                // Audio binary will arrive next via onAudioData — store the text
                pendingAudioSpeakText = msg.text
                lastSpokenText = msg.text
            } else {
                speak(msg.text)
            }

        case .closeAll:
            closeAllWindows()

        case .updateWindow(let msg):
            handleUpdateWindow(msg)

        case .pong:
            break
        }
    }

    // MARK: - ElevenLabs Audio Playback

    func playElevenLabsAudio(_ data: Data) {
        isSpeaking = true
        if let text = pendingAudioSpeakText {
            lastSpokenText = text
            pendingAudioSpeakText = nil
        }

        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = speechDelegate
            audioPlayer?.volume = 0.9
            audioPlayer?.play()
        } catch {
            print("[WindowManager] Audio playback error: \(error.localizedDescription)")
            isSpeaking = false
            // Fallback: if audio fails and we have text, use device TTS
            if let text = lastSpokenText.isEmpty ? nil : lastSpokenText {
                speak(text)
            }
        }
    }

    // MARK: - Window Management

    private func openSpatialWindow(_ msg: OpenWindowMessage) {
        guard openWindows.count < maxConcurrentWindows else {
            speak("Maximum panels reached. Dismiss some windows first, Dave.")
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
        print("[WindowManager] Update request for window: \(msg.windowId)")
    }

    // MARK: - Text-to-Speech (device fallback)

    func speak(_ text: String) {
        lastSpokenText = text
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.85
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: - Delegates

    private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
        weak var manager: WindowManager?

        init(manager: WindowManager) {
            self.manager = manager
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            DispatchQueue.main.async {
                self.manager?.isSpeaking = false
            }
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            DispatchQueue.main.async {
                self.manager?.isSpeaking = false
            }
        }
    }
}
