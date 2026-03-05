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
    }

    private(set) var state: ListeningState = .idle
    private(set) var currentTranscript: String = ""

    var onTranscript: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioBuffer: [Data] = []
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5
    private let wakePhrase = "hey jarvis"
    private var isCapturingCommand = false

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
        isCapturingCommand = false
        audioBuffer.removeAll()
        state = .idle
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
            self?.recognitionRequest?.append(buffer)

            if self?.isCapturingCommand == true {
                self?.appendBufferToCapture(buffer)
            }
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString.lowercased()

                if !self.isCapturingCommand && text.contains(self.wakePhrase) {
                    self.activateCommandCapture()
                }

                if self.isCapturingCommand {
                    let commandText = self.extractCommandAfterWakeWord(from: result.bestTranscription.formattedString)
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

    private func activateCommandCapture() {
        guard !isCapturingCommand else { return }
        isCapturingCommand = true
        audioBuffer.removeAll()
        state = .listening
        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            self?.finishCommandCapture()
        }
    }

    private func finishCommandCapture() {
        isCapturingCommand = false
        silenceTimer?.invalidate()
        silenceTimer = nil

        let transcript = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.isEmpty {
            state = .waitingForWakeWord
            return
        }

        state = .transcribing

        Task {
            let finalTranscript = await transcribeWithWhisper() ?? transcript

            await MainActor.run {
                self.currentTranscript = finalTranscript
                self.onTranscript?(finalTranscript)
                self.audioBuffer.removeAll()
                self.state = .waitingForWakeWord
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
