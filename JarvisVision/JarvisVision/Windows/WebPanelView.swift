import SwiftUI
import WebKit

struct WebPanelView: View {
    let windowId: String
    let payload: WebPanelPayload

    @Environment(WindowManager.self) private var windowManager
    @State private var isLoading = true
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(.white.opacity(0.15))
            webContent
        }
        .glassBackgroundEffect()
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: appeared)
        .onAppear { appeared = true }
    }

    private var headerBar: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
            }

            Text(payload.title ?? payload.url ?? "Web Panel")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            Spacer()

            Button(action: { windowManager.closeWindow(id: windowId) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var webContent: some View {
        WebViewRepresentable(
            url: payload.url,
            html: payload.html,
            isLoading: $isLoading
        )
        .frame(minWidth: 400, idealWidth: 900, minHeight: 300, idealHeight: 650)
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let url: String?
    let html: String?
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = preferences
        config.preferences.isElementFullscreenEnabled = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let html {
            let styledHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body {
                        font-family: -apple-system, system-ui, sans-serif;
                        color: #ffffff;
                        background: transparent;
                        padding: 16px;
                        margin: 0;
                    }
                    a { color: #00d4ff; }
                    table { border-collapse: collapse; width: 100%; }
                    th, td { border: 1px solid rgba(255,255,255,0.15); padding: 8px; text-align: left; }
                    th { background: rgba(255,255,255,0.05); }
                    code { background: rgba(255,255,255,0.1); padding: 2px 6px; border-radius: 4px; }
                    pre { background: rgba(255,255,255,0.05); padding: 12px; border-radius: 8px; overflow-x: auto; }
                </style>
            </head>
            <body>\(html)</body>
            </html>
            """
            webView.loadHTMLString(styledHTML, baseURL: nil)
        } else if let urlString = url, let loadURL = URL(string: urlString) {
            webView.load(URLRequest(url: loadURL))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable

        init(parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
