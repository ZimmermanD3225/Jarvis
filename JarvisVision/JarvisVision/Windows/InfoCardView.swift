import SwiftUI

struct InfoCardView: View {
    let windowId: String
    let payload: InfoCardPayload

    @Environment(WindowManager.self) private var windowManager
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().background(.white.opacity(0.15))
            ScrollView {
                markdownContent
                    .padding(20)
            }
        }
        .frame(maxWidth: 600)
        .glassBackgroundEffect()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.easeOut(duration: 0.4), value: appeared)
        .onAppear { appeared = true }
    }

    private var headerBar: some View {
        HStack {
            Text(payload.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Spacer()

            if let badge = payload.statusBadge, badge != .none {
                statusBadgeView(badge)
            }

            Button(action: copyContent) {
                Image(systemName: "doc.on.doc")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Button(action: { windowManager.closeWindow(id: windowId) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func statusBadgeView(_ badge: StatusBadge) -> some View {
        let (color, label) = badgeInfo(badge)
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func badgeInfo(_ badge: StatusBadge) -> (Color, String) {
        switch badge {
        case .green: return (.green, "Good")
        case .yellow: return (.yellow, "Warning")
        case .red: return (.red, "Critical")
        case .none: return (.clear, "")
        }
    }

    private var markdownContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let attributed = parseMarkdown(payload.content) {
                Text(attributed)
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            } else {
                Text(payload.content)
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
    }

    private func parseMarkdown(_ markdown: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return try? AttributedString(markdown: markdown, options: options)
    }

    private func copyContent() {
        #if os(visionOS) || os(iOS)
        UIPasteboard.general.string = payload.content
        #endif
    }
}
