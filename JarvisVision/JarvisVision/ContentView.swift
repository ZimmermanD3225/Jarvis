import SwiftUI

struct ContentView: View {
    @Environment(WindowManager.self) private var windowManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var webSocket = WebSocketClient()
    @State private var voicePipeline = VoicePipeline()
    @State private var showPermissionAlert = false
    @State private var statusText = "Initializing..."
    @State private var orbScale: CGFloat = 1.0
    @State private var orbOpacity: Double = 0.4

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()

                listeningOrb

                statusLabel

                connectionIndicator

                Spacer()

                windowCounter
            }
            .padding(40)
        }
        .frame(minWidth: 400, minHeight: 400)
        .glassBackgroundEffect()
        .onAppear {
            windowManager.bindActions(open: openWindow, dismiss: dismissWindow)
            setupPipelines()
        }
        .onDisappear {
            voicePipeline.stopListening()
            webSocket.disconnect()
        }
        .alert("Permissions Required", isPresented: $showPermissionAlert) {
            Button("OK") {}
        } message: {
            Text("Jarvis needs microphone and speech recognition access. Please enable them in Settings.")
        }
    }

    // MARK: - Listening Orb

    private var listeningOrb: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(orbGradient)
                .frame(width: 140, height: 140)
                .blur(radius: 30)
                .opacity(orbOpacity * 0.5)
                .scaleEffect(orbScale * 1.3)

            // Inner orb
            Circle()
                .fill(orbGradient)
                .frame(width: 80, height: 80)
                .opacity(orbOpacity)
                .scaleEffect(orbScale)

            // Core
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .opacity(orbOpacity * 1.5)
                .scaleEffect(orbScale * 0.8)
        }
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: orbScale)
        .onChange(of: voicePipeline.state) { _, newState in
            updateOrbAnimation(for: newState)
        }
    }

    private var orbGradient: RadialGradient {
        RadialGradient(
            colors: orbColors,
            center: .center,
            startRadius: 0,
            endRadius: 60
        )
    }

    private var orbColors: [Color] {
        switch voicePipeline.state {
        case .idle:
            return [.gray.opacity(0.3), .gray.opacity(0.1)]
        case .waitingForWakeWord:
            return [.cyan.opacity(0.6), .blue.opacity(0.2)]
        case .listening:
            return [.cyan, .blue.opacity(0.6)]
        case .transcribing:
            return [.purple, .cyan.opacity(0.4)]
        }
    }

    private func updateOrbAnimation(for state: VoicePipeline.ListeningState) {
        switch state {
        case .idle:
            orbScale = 1.0
            orbOpacity = 0.3
        case .waitingForWakeWord:
            orbScale = 1.05
            orbOpacity = 0.4
        case .listening:
            orbScale = 1.2
            orbOpacity = 0.9
        case .transcribing:
            orbScale = 1.1
            orbOpacity = 0.7
        }
    }

    // MARK: - Status

    private var statusLabel: some View {
        VStack(spacing: 8) {
            Text(statusMessage)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            if !voicePipeline.currentTranscript.isEmpty {
                Text("\"\(voicePipeline.currentTranscript)\"")
                    .font(.subheadline)
                    .foregroundStyle(.cyan.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: voicePipeline.state)
    }

    private var statusMessage: String {
        switch voicePipeline.state {
        case .idle:
            return statusText
        case .waitingForWakeWord:
            return "Say \"Hey Jarvis\"..."
        case .listening:
            return "Listening..."
        case .transcribing:
            return "Processing..."
        }
    }

    private var connectionIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)

            Text(connectionLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var connectionColor: Color {
        switch webSocket.state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        }
    }

    private var connectionLabel: String {
        switch webSocket.state {
        case .connected: return "Connected to Mac Mini"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        }
    }

    private var windowCounter: some View {
        Group {
            if windowManager.windowCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.cyan.opacity(0.6))
                    Text("\(windowManager.windowCount) window\(windowManager.windowCount == 1 ? "" : "s") open")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: windowManager.windowCount)
    }

    // MARK: - Setup

    private func setupPipelines() {
        webSocket.onMessage = { message in
            windowManager.handleMessage(message)
        }

        voicePipeline.onTranscript = { transcript in
            webSocket.send(transcript: transcript)
        }

        webSocket.connect()

        Task {
            let granted = await voicePipeline.requestPermissions()
            if granted {
                voicePipeline.startListening()
                statusText = "Ready"
            } else {
                showPermissionAlert = true
                statusText = "Permissions needed"
            }
        }
    }
}
