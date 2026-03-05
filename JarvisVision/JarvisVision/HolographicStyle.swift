import SwiftUI

// MARK: - Jarvis Color Palette

enum JarvisColors {
    static let primary = Color(red: 0.0, green: 0.83, blue: 1.0)       // #00D4FF — arc reactor cyan
    static let secondary = Color(red: 0.0, green: 0.55, blue: 0.85)    // #008CD9 — deep blue
    static let accent = Color(red: 0.4, green: 0.92, blue: 1.0)        // #66EBFF — bright highlight
    static let warm = Color(red: 1.0, green: 0.6, blue: 0.2)           // #FF9933 — warning/energy orange
    static let danger = Color(red: 1.0, green: 0.25, blue: 0.25)       // #FF4040
    static let success = Color(red: 0.2, green: 0.9, blue: 0.4)        // #33E666
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.6)
    static let textDim = Color.white.opacity(0.35)
    static let panelBackground = Color.white.opacity(0.03)

    static let holoBorderGradient = LinearGradient(
        colors: [
            primary.opacity(0.6),
            accent.opacity(0.3),
            primary.opacity(0.1),
            Color.clear,
            primary.opacity(0.1),
            accent.opacity(0.3),
            primary.opacity(0.6),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Holographic Window Border

struct HolographicBorder: ViewModifier {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    @State private var phase: CGFloat = 0

    init(cornerRadius: CGFloat = 20, lineWidth: CGFloat = 1) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [
                                JarvisColors.primary.opacity(0.5),
                                JarvisColors.accent.opacity(0.2),
                                Color.clear,
                                Color.clear,
                                JarvisColors.primary.opacity(0.3),
                                JarvisColors.accent.opacity(0.5),
                            ],
                            center: .center,
                            startAngle: .degrees(phase),
                            endAngle: .degrees(phase + 360)
                        ),
                        lineWidth: lineWidth
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(JarvisColors.primary.opacity(0.08), lineWidth: lineWidth * 3)
                    .blur(radius: 4)
            )
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    phase = 360
                }
            }
    }
}

// MARK: - Scan Line Effect

struct ScanLineOverlay: View {
    @State private var offset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.clear,
                    JarvisColors.primary.opacity(0.04),
                    JarvisColors.primary.opacity(0.08),
                    JarvisColors.primary.opacity(0.04),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .offset(y: offset * geo.size.height)
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    offset = 1.2
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Horizontal Scan Lines (CRT effect)

struct CRTScanLines: View {
    let spacing: CGFloat
    let opacity: Double

    init(spacing: CGFloat = 4, opacity: Double = 0.03) {
        self.spacing = spacing
        self.opacity = opacity
    }

    var body: some View {
        GeometryReader { geo in
            let count = Int(geo.size.height / spacing)
            VStack(spacing: spacing - 0.5) {
                ForEach(0..<count, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(opacity))
                        .frame(height: 0.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Window Header Bar

struct JarvisWindowHeader: View {
    let title: String
    let icon: String?
    let onClose: () -> Void
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(JarvisColors.primary)
            }

            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(JarvisColors.textPrimary)
                .lineLimit(1)

            Spacer()

            if let trailing {
                trailing()
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(JarvisColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Pulsing Status Dot

struct PulsingDot: View {
    let color: Color
    let size: CGFloat
    @State private var isPulsing = false

    init(color: Color, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 2.5, height: size * 2.5)
                .scaleEffect(isPulsing ? 1.0 : 0.5)
                .opacity(isPulsing ? 0 : 0.6)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Typewriter Text

struct TypewriterText: View {
    let fullText: String
    let characterDelay: TimeInterval
    @State private var displayedCount: Int = 0

    init(_ text: String, delay: TimeInterval = 0.03) {
        self.fullText = text
        self.characterDelay = delay
    }

    var body: some View {
        Text(String(fullText.prefix(displayedCount)))
            .onAppear {
                displayedCount = 0
                animateText()
            }
            .onChange(of: fullText) { _, _ in
                displayedCount = 0
                animateText()
            }
    }

    private func animateText() {
        let chars = Array(fullText)
        for (index, _) in chars.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + characterDelay * Double(index)) {
                if displayedCount <= index {
                    displayedCount = index + 1
                }
            }
        }
    }
}

// MARK: - Audio Waveform Visualizer

struct AudioWaveform: View {
    let levels: [CGFloat]
    let barCount: Int
    let color: Color

    init(levels: [CGFloat] = [], barCount: Int = 32, color: Color = JarvisColors.primary) {
        self.levels = levels
        self.barCount = barCount
        self.color = color
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? levels[index] : CGFloat.random(in: 0.05...0.15)
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.4), color],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: max(2, level * 40))
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
    }
}

// MARK: - Boot Sequence Text

struct BootSequenceLine: Identifiable {
    let id = UUID()
    let text: String
    let delay: TimeInterval
    let isHighlight: Bool

    init(_ text: String, delay: TimeInterval, highlight: Bool = false) {
        self.text = text
        self.delay = delay
        self.isHighlight = highlight
    }
}

// MARK: - View Extensions

extension View {
    func holographicBorder(cornerRadius: CGFloat = 20, lineWidth: CGFloat = 1) -> some View {
        modifier(HolographicBorder(cornerRadius: cornerRadius, lineWidth: lineWidth))
    }

    func jarvisPanel() -> some View {
        self
            .background(JarvisColors.panelBackground)
            .glassBackgroundEffect()
            .holographicBorder()
            .overlay(ScanLineOverlay())
    }
}
