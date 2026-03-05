import SwiftUI
import WebKit

struct WebPanelView: View {
    let windowId: String
    let payload: WebPanelPayload

    @Environment(WindowManager.self) private var windowManager
    @State private var isLoading = true
    @State private var appeared = false
    @State private var loadProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.body)
                    .foregroundStyle(JarvisColors.primary)

                Text(payload.title ?? domainFromURL ?? "Web Panel")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(JarvisColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(JarvisColors.primary)
                        Text("LOADING")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(JarvisColors.textDim)
                    }
                }

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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Loading bar
            if isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(JarvisColors.primary)
                        .frame(width: geo.size.width * loadProgress, height: 1.5)
                        .animation(.linear(duration: 0.3), value: loadProgress)
                }
                .frame(height: 1.5)
            } else {
                Divider().background(JarvisColors.primary.opacity(0.1))
            }

            // Web content
            WebViewRepresentable(
                url: payload.url,
                html: payload.html,
                isLoading: $isLoading,
                loadProgress: $loadProgress
            )
            .frame(minWidth: 400, idealWidth: 900, minHeight: 300, idealHeight: 650)
        }
        .jarvisPanel()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
        .onAppear { appeared = true }
    }

    private var domainFromURL: String? {
        guard let urlString = payload.url, let url = URL(string: urlString) else { return nil }
        return url.host
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let url: String?
    let html: String?
    @Binding var isLoading: Bool
    @Binding var loadProgress: Double

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
        webView.allowsBackForwardNavigationGestures = false

        // Observe estimated progress
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), context: nil)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.hasLoaded { return }
        context.coordinator.hasLoaded = true

        if let html {
            let styledHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    * { box-sizing: border-box; }
                    body {
                        font-family: -apple-system, 'SF Pro Display', system-ui, sans-serif;
                        color: rgba(255,255,255,0.92);
                        background: transparent;
                        padding: 20px;
                        margin: 0;
                        line-height: 1.6;
                        font-size: 14px;
                    }
                    h1, h2, h3 { color: #00D4FF; font-weight: 600; margin-top: 1.2em; }
                    h1 { font-size: 1.6em; border-bottom: 1px solid rgba(0,212,255,0.15); padding-bottom: 8px; }
                    h2 { font-size: 1.3em; }
                    a { color: #66EBFF; text-decoration: none; }
                    a:hover { text-decoration: underline; }
                    table { border-collapse: collapse; width: 100%; margin: 12px 0; }
                    th, td {
                        border: 1px solid rgba(0,212,255,0.12);
                        padding: 10px 12px;
                        text-align: left;
                        font-size: 13px;
                    }
                    th {
                        background: rgba(0,212,255,0.06);
                        color: #00D4FF;
                        font-weight: 600;
                        text-transform: uppercase;
                        font-size: 11px;
                        letter-spacing: 0.5px;
                    }
                    tr:hover td { background: rgba(255,255,255,0.02); }
                    code {
                        background: rgba(0,212,255,0.08);
                        color: #66EBFF;
                        padding: 2px 6px;
                        border-radius: 4px;
                        font-family: 'SF Mono', monospace;
                        font-size: 0.9em;
                    }
                    pre {
                        background: rgba(0,0,0,0.3);
                        border: 1px solid rgba(0,212,255,0.1);
                        padding: 14px;
                        border-radius: 8px;
                        overflow-x: auto;
                        font-size: 13px;
                    }
                    pre code { background: none; padding: 0; }
                    blockquote {
                        border-left: 3px solid rgba(0,212,255,0.3);
                        margin: 12px 0;
                        padding: 8px 16px;
                        color: rgba(255,255,255,0.7);
                    }
                    hr { border: none; border-top: 1px solid rgba(0,212,255,0.1); margin: 20px 0; }
                    ::-webkit-scrollbar { width: 6px; }
                    ::-webkit-scrollbar-track { background: transparent; }
                    ::-webkit-scrollbar-thumb { background: rgba(0,212,255,0.2); border-radius: 3px; }
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
        var hasLoaded = false

        init(parent: WebViewRepresentable) {
            self.parent = parent
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "estimatedProgress", let webView = object as? WKWebView {
                DispatchQueue.main.async {
                    self.parent.loadProgress = webView.estimatedProgress
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadProgress = 1.0
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow initial load and same-origin navigations, block everything else
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
