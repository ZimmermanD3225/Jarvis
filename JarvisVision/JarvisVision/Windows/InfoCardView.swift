import SwiftUI

struct InfoCardView: View {
    let windowId: String
    let payload: InfoCardPayload

    @Environment(WindowManager.self) private var windowManager
    @State private var appeared = false
    @State private var copyConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.body)
                    .foregroundStyle(JarvisColors.primary)

                Text(payload.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(JarvisColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if let badge = payload.statusBadge, badge != .none {
                    statusBadgeView(badge)
                }

                Button(action: copyContent) {
                    Image(systemName: copyConfirm ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(copyConfirm ? JarvisColors.success : JarvisColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: { windowManager.closeWindow(id: windowId) }) {
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

            Divider().background(JarvisColors.primary.opacity(0.1))

            // Content
            ScrollView {
                markdownContent
                    .padding(20)
            }
        }
        .frame(maxWidth: 600)
        .jarvisPanel()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
        .onAppear { appeared = true }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadgeView(_ badge: StatusBadge) -> some View {
        let (color, label) = badgeInfo(badge)
        HStack(spacing: 5) {
            PulsingDot(color: color, size: 6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private func badgeInfo(_ badge: StatusBadge) -> (Color, String) {
        switch badge {
        case .green: return (JarvisColors.success, "Good")
        case .yellow: return (JarvisColors.warm, "Warning")
        case .red: return (JarvisColors.danger, "Critical")
        case .none: return (.clear, "")
        }
    }

    // MARK: - Markdown Content

    private var markdownContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let attributed = parseMarkdown(payload.content) {
                Text(attributed)
                    .font(.system(size: 14))
                    .foregroundStyle(JarvisColors.textPrimary)
                    .textSelection(.enabled)
                    .tint(JarvisColors.primary)
            } else {
                // Fallback: render raw text with monospace for that Jarvis feel
                Text(payload.content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(JarvisColors.textPrimary.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
    }

    private func parseMarkdown(_ markdown: String) -> AttributedString? {
        // Use .full to properly render headers, lists, tables, etc.
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        return try? AttributedString(markdown: markdown, options: options)
    }

    // MARK: - Copy

    private func copyContent() {
        #if os(visionOS) || os(iOS)
        UIPasteboard.general.string = payload.content
        #endif
        copyConfirm = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyConfirm = false
        }
    }
}
