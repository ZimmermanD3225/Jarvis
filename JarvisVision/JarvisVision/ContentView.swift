import SwiftUI

struct ContentView: View {
    @Environment(WindowManager.self) private var windowManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var webSocket = WebSocketClient()
    @State private var voicePipeline = VoicePipeline()
    @State private var showPermissionAlert = false

    // Boot sequence
    @State private var bootPhase: BootPhase = .off
    @State private var bootLines: [BootSequenceLine] = []
    @State private var visibleBootLines: [BootSequenceLine] = []

    // Orb animation
    @State private var ringRotation1: Double = 0
    @State private var ringRotation2: Double = 0
    @State private var ringRotation3: Double = 0
    @State private var coreScale: CGFloat = 0.0
    @State private var corePulse: CGFloat = 1.0
    @State private var orbGlow: CGFloat = 0.0

    // Waveform
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 40)
    @State private var waveformTimer: Timer?

    enum BootPhase {
        case off, booting, ready
    }

    var body: some View {
        ZStack {
            // Ambient CRT scan lines across entire panel
            CRTScanLines(spacing: 3, opacity: 0.015)

            VStack(spacing: 0) {
                hudTopBar
                    .opacity(bootPhase == .ready ? 1 : 0)
                    .animation(.easeIn(duration: 0.6), value: bootPhase)

                Spacer()

                if bootPhase == .booting {
                    bootSequenceView
                        .transition(.opacity)
                } else if bootPhase == .ready {
                    mainInterface
                        .transition(.opacity)
                }

                Spacer()

                hudBottomBar
                    .opacity(bootPhase == .ready ? 1 : 0)
                    .animation(.easeIn(duration: 0.6), value: bootPhase)
            }
            .padding(24)
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 550, idealHeight: 650)
        .jarvisPanel()
        .onAppear {
            windowManager.bindActions(open: openWindow, dismiss: dismissWindow)
            startBootSequence()
        }
        .onDisappear {
            voicePipeline.stopListening()
            webSocket.disconnect()
            waveformTimer?.invalidate()
        }
        .alert("Permissions Required", isPresented: $showPermissionAlert) {
            Button("OK") {}
        } message: {
            Text("Jarvis needs microphone and speech recognition access. Please enable them in Settings.")
        }
    }

    // MARK: - HUD Top Bar

    private var hudTopBar: some View {
        HStack {
            // System status
            HStack(spacing: 6) {
                PulsingDot(color: connectionColor, size: 6)
                Text(connectionLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(JarvisColors.textDim)
            }

            Spacer()

            Text("J.A.R.V.I.S.")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(JarvisColors.primary.opacity(0.5))
                .tracking(4)

            Spacer()

            // Time display
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(timeString(from: timeline.date))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(JarvisColors.textDim)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - HUD Bottom Bar

    private var hudBottomBar: some View {
        HStack(spacing: 16) {
            // Window count
            if windowManager.windowCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 10))
                        .foregroundStyle(JarvisColors.primary.opacity(0.5))
                    Text("\(windowManager.windowCount) PANEL\(windowManager.windowCount == 1 ? "" : "S")")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(JarvisColors.textDim)
                }
                .transition(.opacity)
            }

            Spacer()

            // Pipeline state indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(stateIndicatorColor)
                    .frame(width: 5, height: 5)
                Text(stateIndicatorLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(JarvisColors.textDim)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.3), value: windowManager.windowCount)
    }

    // MARK: - Boot Sequence

    private var bootSequenceView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleBootLines) { line in
                Text(line.text)
                    .font(.system(size: 11, weight: line.isHighlight ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(line.isHighlight ? JarvisColors.primary : JarvisColors.textDim)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: visibleBootLines.count)
    }

    private func startBootSequence() {
        bootPhase = .booting

        bootLines = [
            BootSequenceLine("Initializing J.A.R.V.I.S. v1.0...", delay: 0.0),
            BootSequenceLine("Loading spatial rendering engine", delay: 0.3),
            BootSequenceLine("AVAudioEngine .............. OK", delay: 0.6),
            BootSequenceLine("Speech recognizer .......... OK", delay: 0.9),
            BootSequenceLine("Whisper STT endpoint ....... OK", delay: 1.1),
            BootSequenceLine("WebSocket client ........... CONNECTING", delay: 1.4),
            BootSequenceLine("Connecting to Mac Mini gateway", delay: 1.7),
            BootSequenceLine("Claude API bridge .......... STANDBY", delay: 2.0),
            BootSequenceLine("Spatial window manager ..... READY", delay: 2.3),
            BootSequenceLine("Voice pipeline ............. ACTIVE", delay: 2.6),
            BootSequenceLine("", delay: 2.9),
            BootSequenceLine("All systems nominal. Good evening, Dave.", delay: 3.0, highlight: true),
        ]

        for line in bootLines {
            DispatchQueue.main.asyncAfter(deadline: .now() + line.delay) {
                visibleBootLines.append(line)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeInOut(duration: 0.6)) {
                bootPhase = .ready
            }
            setupPipelines()
            startOrbAnimations()
        }
    }

    // MARK: - Main Interface (Post-Boot)

    private var mainInterface: some View {
        VStack(spacing: 24) {
            arcReactorOrb

            // Status text
            VStack(spacing: 8) {
                Text(statusMessage)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(JarvisColors.textPrimary)
                    .animation(.easeInOut(duration: 0.3), value: voicePipeline.state)

                if !voicePipeline.currentTranscript.isEmpty {
                    Text(voicePipeline.currentTranscript)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(JarvisColors.primary.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                        .animation(.easeOut(duration: 0.2), value: voicePipeline.currentTranscript)
                }
            }

            // Audio waveform (visible when listening)
            if voicePipeline.state == .listening {
                AudioWaveform(levels: audioLevels, barCount: 40, color: JarvisColors.primary)
                    .frame(height: 44)
                    .frame(maxWidth: 300)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .center)))
                    .animation(.easeInOut(duration: 0.3), value: voicePipeline.state)
            }
        }
    }

    // MARK: - Arc Reactor Orb

    private var arcReactorOrb: some View {
        ZStack {
            // Outer ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            JarvisColors.primary.opacity(0.15 * orbGlow),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)

            // Ring 3 — outermost, slow rotation
            orbRing(radius: 110, dashPattern: [8, 16], lineWidth: 0.8, opacity: 0.2)
                .rotationEffect(.degrees(ringRotation3))

            // Ring 2 — middle ring with thicker segments
            orbRing(radius: 85, dashPattern: [20, 10, 4, 10], lineWidth: 1.2, opacity: 0.35)
                .rotationEffect(.degrees(ringRotation2))

            // Ring 1 — inner ring, fastest
            orbRing(radius: 60, dashPattern: [12, 8], lineWidth: 1.5, opacity: 0.5)
                .rotationEffect(.degrees(ringRotation1))

            // Tick marks on outer ring
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) * 15.0
                let isMain = i % 6 == 0
                Rectangle()
                    .fill(JarvisColors.primary.opacity(isMain ? 0.3 : 0.1))
                    .frame(width: isMain ? 1.5 : 0.8, height: isMain ? 12 : 6)
                    .offset(y: -105)
                    .rotationEffect(.degrees(angle))
            }

            // Energy core — outer
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            JarvisColors.accent.opacity(0.6),
                            JarvisColors.primary.opacity(0.3),
                            JarvisColors.secondary.opacity(0.1),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 35
                    )
                )
                .frame(width: 70, height: 70)
                .scaleEffect(coreScale * corePulse)
                .blur(radius: 1)

            // Energy core — bright center
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, JarvisColors.accent, JarvisColors.primary.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 18
                    )
                )
                .frame(width: 36, height: 36)
                .scaleEffect(coreScale * corePulse)

            // Tiny core point
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
                .scaleEffect(coreScale)
                .opacity(Double(corePulse))
        }
        .frame(width: 240, height: 240)
    }

    private func orbRing(radius: CGFloat, dashPattern: [CGFloat], lineWidth: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(
                JarvisColors.primary.opacity(opacity * Double(orbGlow)),
                style: StrokeStyle(lineWidth: lineWidth, dash: dashPattern)
            )
            .frame(width: radius * 2, height: radius * 2)
    }

    // MARK: - Orb Animations

    private func startOrbAnimations() {
        // Core appears
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            coreScale = 1.0
        }

        // Glow fades in
        withAnimation(.easeIn(duration: 1.2)) {
            orbGlow = 1.0
        }

        // Ring rotations — different speeds, different directions
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            ringRotation1 = 360
        }
        withAnimation(.linear(duration: 35).repeatForever(autoreverses: false)) {
            ringRotation2 = -360
        }
        withAnimation(.linear(duration: 55).repeatForever(autoreverses: false)) {
            ringRotation3 = 360
        }

        // Core breathing pulse
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            corePulse = 1.08
        }

        // Start waveform updates
        startWaveformSimulation()
    }

    private func startWaveformSimulation() {
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            let levels = voicePipeline.currentAudioLevels
            if !levels.isEmpty {
                audioLevels = levels
            } else if voicePipeline.state == .listening {
                // Subtle idle animation when listening but no level data yet
                audioLevels = (0..<40).map { _ in CGFloat.random(in: 0.02...0.12) }
            }
        }
    }

    // MARK: - Status

    private var statusMessage: String {
        switch voicePipeline.state {
        case .idle:
            return "OFFLINE"
        case .waitingForWakeWord:
            return "AWAITING COMMAND"
        case .listening:
            return "LISTENING"
        case .transcribing:
            return "PROCESSING"
        case .conversational:
            return "ACTIVE SESSION"
        }
    }

    private var connectionColor: Color {
        switch webSocket.state {
        case .connected: return JarvisColors.success
        case .connecting: return JarvisColors.warm
        case .disconnected: return JarvisColors.danger
        }
    }

    private var connectionLabel: String {
        switch webSocket.state {
        case .connected: return "GATEWAY LINK"
        case .connecting: return "CONNECTING"
        case .disconnected: return "NO LINK"
        }
    }

    private var stateIndicatorColor: Color {
        switch voicePipeline.state {
        case .idle: return JarvisColors.textDim
        case .waitingForWakeWord: return JarvisColors.primary.opacity(0.5)
        case .listening, .conversational: return JarvisColors.success
        case .transcribing: return JarvisColors.warm
        }
    }

    private var stateIndicatorLabel: String {
        switch voicePipeline.state {
        case .idle: return "STT IDLE"
        case .waitingForWakeWord: return "WAKE WORD"
        case .listening: return "STT ACTIVE"
        case .conversational: return "CONV MODE"
        case .transcribing: return "WHISPER"
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - Setup

    private func setupPipelines() {
        webSocket.onMessage = { message in
            windowManager.handleMessage(message)

            // When Jarvis responds, switch to conversational mode briefly
            if case .speakResponse = message {
                voicePipeline.enterConversationalMode()
            }
        }

        // Handle ElevenLabs audio binary from the server
        webSocket.onAudioData = { data in
            windowManager.playElevenLabsAudio(data)
        }

        voicePipeline.onTranscript = { transcript in
            webSocket.send(transcript: transcript)
        }

        webSocket.connect()

        Task {
            let granted = await voicePipeline.requestPermissions()
            if granted {
                voicePipeline.startListening()
            } else {
                showPermissionAlert = true
            }
        }
    }
}
