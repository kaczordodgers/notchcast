import Foundation
import WebKit

@MainActor
final class WebpageExtractor: NSObject, WKNavigationDelegate {
    enum Failure: LocalizedError {
        case inUse, unavailable(Int), unsupportedContent, blocked, noContent, tooLarge, timedOut, renderFailed

        var errorDescription: String? {
            switch self {
            case .inUse: String(localized: "A webpage is already being saved.")
            case .unavailable(let status): String(localized: "The webpage returned HTTP status \(status).")
            case .unsupportedContent: String(localized: "This URL does not contain an HTML webpage.")
            case .blocked: String(localized: "The webpage requires sign-in or a bot check.")
            case .noContent: String(localized: "The webpage contains no readable article.")
            case .tooLarge: String(localized: "The webpage is too large to save.")
            case .timedOut: String(localized: "The webpage took too long to load.")
            case .renderFailed: String(localized: "The webpage could not be rendered.")
            }
        }
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var operationID: UUID?
    private var loaded = false

    func extract(_ source: URL) async throws -> WebpageArticle {
        guard operationID == nil else { throw Failure.inUse }
        try PublicWebAddress.validate(source)
        try Task.checkCancellation()
        let id = UUID()
        operationID = id
        let proxy: PublicWebProxy
        do { proxy = try PublicWebProxy() } catch { operationID = nil; throw error }
        defer {
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView = nil
            proxy.stop()
            operationID = nil
            loaded = false
        }
        return try await withTaskCancellationHandler {
            let proxyConfiguration = try await proxy.start()
            let configuration = try await WebpageWebViewConfiguration.make(proxy: proxyConfiguration)
            try Task.checkCancellation()
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 2200), configuration: configuration)
            view.navigationDelegate = self
            webView = view
            let timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.finish(.failure(Failure.timedOut))
                view.stopLoading()
            }
            defer { timeout.cancel() }
            try await withCheckedThrowingContinuation { (pending: CheckedContinuation<Void, any Error>) in
                continuation = pending
                view.load(URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(750))
            let value = try await view.callAsyncJavaScript(WebpageExtraction.script, arguments: [:],
                                                           in: nil, contentWorld: .defaultClient)
            try Task.checkCancellation()
            guard let json = value as? String, let data = json.data(using: .utf8),
                  let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.renderFailed }
            if fields["blocked"] as? Bool == true { throw Failure.blocked }
            if fields["tooLarge"] as? Bool == true { throw Failure.tooLarge }
            guard fields["readable"] as? Bool == true,
                  let html = fields["html"] as? String, let title = fields["title"] as? String,
                  let author = fields["author"] as? String else { throw Failure.noContent }
            let baseURL = (fields["baseURL"] as? String).flatMap(URL.init(string:)) ?? view.url ?? source
            let article = WebpageArticle(title: title, author: author, published: fields["published"] as? String,
                                         source: source, baseURL: baseURL, html: html)
            return article
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.operationID == id else { return }
                self.finish(.failure(CancellationError()))
                self.webView?.stopLoading()
                proxy.stop()
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
        -> WKNavigationActionPolicy {
        guard webView === self.webView, !loaded, let url = navigationAction.request.url else { return .cancel }
        do { try PublicWebAddress.validate(url) } catch {
            if navigationAction.targetFrame?.isMainFrame == true { finish(.failure(error)) }
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async
        -> WKNavigationResponsePolicy {
        guard webView === self.webView else { return .cancel }
        guard navigationResponse.isForMainFrame else { return .allow }
        if let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            finish(.failure(Failure.unavailable(response.statusCode)))
            return .cancel
        }
        guard navigationResponse.canShowMIMEType,
              ["text/html", "application/xhtml+xml"].contains(navigationResponse.response.mimeType ?? "") else {
            finish(.failure(Failure.unsupportedContent))
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard webView === self.webView else { return }
        loaded = true
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        guard webView === self.webView else { return }
        finish(.failure(Failure.renderFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        guard webView === self.webView else { return }
        finish(.failure(Failure.renderFailed))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        finish(.failure(Failure.renderFailed))
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? (.performDefaultHandling, nil) : (.cancelAuthenticationChallenge, nil)
    }

    private func finish(_ result: Result<Void, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
