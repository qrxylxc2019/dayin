import SwiftUI
import WebKit

// MARK: - WKWebView 封装

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var currentUrl: String
    let promptRequest: WebPromptRequest?
    let onPromptResult: (String?) -> Void
    private let pageZoom: CGFloat = 1.0

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = pageZoom
        webView.load(URLRequest(url: url))
        context.coordinator.receive(promptRequest, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = pageZoom
        context.coordinator.parent = self
        // 地址栏主动变更时加载新地址
        if let target = context.coordinator.pendingUrl, target != context.coordinator.loadedUrl {
            context.coordinator.loadedUrl = target
            context.coordinator.pageReady = false
            webView.load(URLRequest(url: target))
        }
        context.coordinator.receive(promptRequest, in: webView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var pendingUrl: URL?
        var loadedUrl: URL?
        var pendingPrompt: WebPromptRequest?
        var handledPromptID: UUID?
        var pageReady = false

        init(_ parent: WebView) {
            self.parent = parent
            self.pendingUrl = parent.url
            self.loadedUrl = parent.url
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.pageZoom = parent.pageZoom
            pageReady = true
            // 跳转/重定向后回写地址栏
            let s = webView.url?.absoluteString ?? ""
            DispatchQueue.main.async { self.parent.currentUrl = s }
            deliverPromptIfPossible(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let s = webView.url?.absoluteString ?? ""
            DispatchQueue.main.async { self.parent.currentUrl = s }
            failPendingPrompt("网页加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            failPendingPrompt("网页加载失败：\(error.localizedDescription)")
        }

        func receive(_ request: WebPromptRequest?, in webView: WKWebView) {
            guard let request, request.id != handledPromptID else { return }
            pendingPrompt = request

            let targetURL = parent.url
            if webView.url?.host?.lowercased() != targetURL.host?.lowercased() {
                if loadedUrl == targetURL, !pageReady { return }
                pendingUrl = targetURL
                loadedUrl = targetURL
                pageReady = false
                webView.load(URLRequest(url: targetURL))
                return
            }
            deliverPromptIfPossible(in: webView)
        }

        private func deliverPromptIfPossible(in webView: WKWebView) {
            guard pageReady, let request = pendingPrompt else { return }
            let promptJSON = Self.javaScriptLiteral(request.prompt)
            let script = """
            (function() {
              return new Promise(function(resolve) {
                var findInput = function() {
                  return document.querySelector('textarea[name="search"]')
                    || document.querySelector('textarea.d96f2d2a')
                    || document.querySelector('textarea._27c9245')
                    || document.querySelector('textarea')
                    || document.querySelector('[contenteditable="true"][role="textbox"]')
                    || document.querySelector('div[contenteditable="true"]');
                };
                var inputAttempts = 0;
                var inputTimer = setInterval(function() {
                  inputAttempts += 1;
                  var input = findInput();
                  if (!input) {
                    if (inputAttempts >= 50) {
                      clearInterval(inputTimer);
                      resolve({ success: false, error: '未找到输入框，请确认 AI 网页已登录并加载完成' });
                    }
                    return;
                  }
                  clearInterval(inputTimer);

                  var text = \(promptJSON);
                  try { input.focus(); } catch (e) {}
                  if (input instanceof HTMLTextAreaElement || input instanceof HTMLInputElement) {
                    var proto = input instanceof HTMLTextAreaElement
                      ? window.HTMLTextAreaElement.prototype
                      : window.HTMLInputElement.prototype;
                    var descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
                    if (descriptor && descriptor.set) descriptor.set.call(input, text);
                    else input.value = text;
                  } else {
                    var inserted = false;
                    try {
                      document.execCommand('selectAll', false, null);
                      inserted = document.execCommand('insertText', false, text);
                    } catch (e) {}
                    if (!inserted) input.textContent = text;
                  }
                  try {
                    input.dispatchEvent(new InputEvent('input', {
                      bubbles: true,
                      inputType: 'insertText',
                      data: text
                    }));
                  } catch (e) {
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                  }
                  input.dispatchEvent(new Event('change', { bubbles: true }));

                  var attempts = 0;
                  var timer = setInterval(function() {
                    attempts += 1;
                    var candidates = Array.prototype.slice.call(document.querySelectorAll(
                      'button[type="submit"], button[data-testid*="send"], button[aria-label*="发送"], button[aria-label*="Send"], div[role="button"]'
                    ));
                    var sendButton = candidates.find(function(button) {
                      var className = String(button.className || '');
                      var label = String(button.getAttribute('aria-label') || '');
                      return !button.disabled
                        && !className.includes('disabled')
                        && (className.includes('ds-button--primary')
                          || label.includes('发送')
                          || label.toLowerCase().includes('send')
                          || button.getAttribute('type') === 'submit');
                    });
                    if (sendButton) {
                      clearInterval(timer);
                      sendButton.click();
                      resolve({ success: true });
                    } else if (attempts >= 30) {
                      clearInterval(timer);
                      try {
                        input.dispatchEvent(new KeyboardEvent('keydown', {
                          bubbles: true,
                          cancelable: true,
                          key: 'Enter',
                          code: 'Enter',
                          keyCode: 13,
                          which: 13
                        }));
                      } catch (e) {}
                      resolve({ success: true });
                    }
                  }, 100);
                }, 100);
              });
            })();
            """

            handledPromptID = request.id
            pendingPrompt = nil
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    DispatchQueue.main.async {
                        self.parent.onPromptResult("填入失败：\(error.localizedDescription)")
                    }
                    return
                }
                let response = result as? [String: Any]
                let success = response?["success"] as? Bool ?? false
                let message = response?["error"] as? String
                DispatchQueue.main.async {
                    self.parent.onPromptResult(success ? nil : (message ?? "填入失败"))
                }
            }
        }

        private func failPendingPrompt(_ message: String) {
            guard let request = pendingPrompt else { return }
            handledPromptID = request.id
            pendingPrompt = nil
            DispatchQueue.main.async { self.parent.onPromptResult(message) }
        }

        private static func javaScriptLiteral(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let json = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return String(json.dropFirst().dropLast())
        }
    }
}

// MARK: - 左侧 AI 网页

private enum AIWebSite: String, CaseIterable, Identifiable {
    case doubao
    case deepSeek

    var id: Self { self }

    var name: String {
        switch self {
        case .doubao: "豆包"
        case .deepSeek: "DeepSeek"
        }
    }

    var url: URL {
        switch self {
        case .doubao: URL(string: "https://www.doubao.com/chat/")!
        case .deepSeek: URL(string: "https://chat.deepseek.com/")!
        }
    }
}

struct WebPane: View {
    @Environment(AppModel.self) private var model

    @State private var selectedSite: AIWebSite = .deepSeek
    @State private var displayUrl = "https://chat.deepseek.com/"
    @State private var loadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            // AI 网页下拉选择
            HStack(spacing: 8) {
                Image(systemName: "globe.asia.australia")
                    .foregroundStyle(.secondary)
                Picker("选择 AI 网页", selection: $selectedSite) {
                    ForEach(AIWebSite.allCases) { site in
                        Text(site.name).tag(site)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)

            Divider()

            // 网页
            GeometryReader { geometry in
                WebView(
                    url: selectedSite.url,
                    currentUrl: $displayUrl,
                    promptRequest: model.webPromptRequest
                ) { _ in }
                    .id(loadToken)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onChange(of: selectedSite) { _, site in
            displayUrl = site.url.absoluteString
            loadToken = UUID()
        }
    }
}
