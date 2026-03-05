import AVFoundation
import Speech
import Foundation
import Observation

@Observable
final class VoicePipeline {
    enum ListeningState {
        case idle
        case waitingForWakeWord
        case listening
        case transcribing
        case conversational  // After Jarvis responds — stays listening without wake word
    }

    private(set) var state: ListeningState = .idle
    private(set) var currentTranscript: String = ""
    private(set) var currentAudioLevels: [CGFloat] = []

    var onTranscript: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioBuffer: [Data] = []
    private var silenceTimer: Timer?
    private var conversationalTimeout: Timer?

    // Tunable thresholds
    private let commandSilenceThreshold: TimeInterval = 2.0
    private let conversationalSilenceThreshold: TimeInterval = 3.5  // Longer for thinking out loud
    private let conversationalWindowDuration: TimeInterval = 30.0   // Stay conversational for 30s after Jarvis speaks
    private let wakePhrase = "hey jarvis"
    private var isCapturingCommand = false

    // Audio level tracking
    private let levelSampleCount = 40
    private var rawLevels: [Float] = []

    var currentSilenceThreshold: TimeInterval {
        state == .conversational ? conversationalSilenceThreshold : commandSilenceThreshold
    }

    func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        return micGranted && speechGranted
    }

    func startListening() {
        guard state == .idle else { return }
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        state = .waitingForWakeWord
        startWakeWordDetection()
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        conversationalTimeout?.invalidate()
        conversationalTimeout = nil
        isCapturingCommand = false
        audioBuffer.removeAll()
        rawLevels.removeAll()
        currentAudioLevels.removeAll()
        state = .idle
    }

    func enterConversationalMode() {
        conversationalTimeout?.invalidate()

        if state == .waitingForWakeWord || state == .listening {
            state = .conversational
        }

        // Auto-revert to wake-word mode after the conversational window expires
        conversationalTimeout = Timer.scheduledTimer(withTimeInterval: conversationalWindowDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.state == .conversational {
                DispatchQueue.main.async {
                    self.state = .waitingForWakeWord
                }
            }
        }
    }

    // MARK: - Wake Word Detection (SFSpeechRecognizer — on-device)

    private func startWakeWordDetection() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            print("[Voice] Speech recognizer unavailable")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            self.updateAudioLevels(buffer: buffer)

            if self.isCapturingCommand {
                self.appendBufferToCapture(buffer)
            }
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString.lowercased()

                // In conversational mode: any speech triggers command capture (no wake word needed)
                if self.state == .conversational && !self.isCapturingCommand {
                    let recentText = self.recentTranscriptionText(from: result.bestTranscription)
                    if !recentText.isEmpty {
                        self.activateCommandCapture(skipWakeWord: true)
                    }
                }

                // In wake-word mode: listen for "hey jarvis"
                if !self.isCapturingCommand && text.contains(self.wakePhrase) {
                    self.activateCommandCapture(skipWakeWord: false)
                }

                if self.isCapturingCommand {
                    let commandText: String
                    if self.state == .conversational {
                        commandText = self.recentTranscriptionText(from: result.bestTranscription)
                    } else {
                        commandText = self.extractCommandAfterWakeWord(from: result.bestTranscription.formattedString)
                    }

                    DispatchQueue.main.async {
                        self.currentTranscript = commandText
                    }
                    self.resetSilenceTimer()
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                self.restartWakeWordDetection()
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("[Voice] Audio engine start error: \(error.localizedDescription)")
        }
    }

    // MARK: - Audio Level Metering

    private func updateAudioLevels(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let channelSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // RMS level
        let rms = sqrt(channelSamples.map { $0 * $0 }.reduce(0, +) / Float(frameLength))
        let normalizedLevel = min(1.0, rms * 5.0) // Amplify for visual impact

        rawLevels.append(normalizedLevel)
        if rawLevels.count > levelSampleCount {
            rawLevels.removeFirst(rawLevels.count - levelSampleCount)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentAudioLevels = self.rawLevels.map { CGFloat($0) }
        }
    }

    // MARK: - Command Capture

    private func activateCommandCapture(skipWakeWord: Bool) {
        guard !isCapturingCommand else { return }
        isCapturingCommand = true
        audioBuffer.removeAll()
        if state != .conversational {
            state = .listening
        }
        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: currentSilenceThreshold, repeats: false) { [weak self] _ in
            self?.finishCommandCapture()
        }
    }

    private func finishCommandCapture() {
        isCapturingCommand = false
        silenceTimer?.invalidate()
        silenceTimer = nil

        let transcript = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.isEmpty {
            state = state == .conversational ? .conversational : .waitingForWakeWord
            return
        }

        let returnState = state == .conversational ? ListeningState.conversational : .waitingForWakeWord
        state = .transcribing

        Task {
            let finalTranscript = await transcribeWithWhisper() ?? transcript

            await MainActor.run {
                self.currentTranscript = finalTranscript
                self.onTranscript?(finalTranscript)
                self.audioBuffer.removeAll()
                self.state = returnState
                self.currentTranscript = ""
            }
        }
    }

    private func appendBufferToCapture(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)
        audioBuffer.append(data)
    }

    private func extractCommandAfterWakeWord(from fullText: String) -> String {
        let lower = fullText.lowercased()
        guard let range = lower.range(of: wakePhrase) else { return fullText }
        let afterWake = fullText[range.upperBound...]
        return afterWake.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recentTranscriptionText(from transcription: SFTranscription) -> String {
        // Get text from the last few seconds of transcription segments
        let segments = transcription.segments
        guard !segments.isEmpty else { return "" }
        let recentCutoff = segments.last!.timestamp - 10.0  // Last 10 seconds
        let recentSegments = segments.filter { $0.timestamp >= recentCutoff }
        return recentSegments.map { $0.substring }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restartWakeWordDetection() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)

        if state != .idle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startWakeWordDetection()
            }
        }
    }

    // MARK: - Whisper API Transcription

    private func transcribeWithWhisper() async -> String? {
        guard !audioBuffer.isEmpty else { return nil }

        let combinedData = audioBuffer.reduce(Data()) { $0 + $1 }
        let wavData = createWAVFile(from: combinedData)

        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String else {
            print("[Voice] No OpenAI API key found")
            return nil
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
            return response.text
        } catch {
            print("[Voice] Whisper API error: \(error.localizedDescription)")
            return nil
        }
    }

    private func createWAVFile(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let bitsPerSample: UInt16 = 32
        let channels: UInt16 = 1
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: (36 + dataSize).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(3).littleEndian) { Data($0) }) // IEEE float
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        header.append(pcmData)

        return header
    }
}

private struct WhisperResponse: Decodable {
    let text: String
}
