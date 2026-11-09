// notchcast-sources: Tinycast/Features/Downloads/Webpage/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
import AppKit
import Foundation
import Network
import WebKit

@main
@MainActor
struct DownloadsWebpageTests {
    static var passes = 0
    static var failures = 0
    static let base = URL(string: "https://example.com/articles/page")!

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func markdown(_ html: String) -> String { HTMLMarkdown.convert(html, baseURL: base) }

    static func main() async throws {
        converter()
        addresses()
        frontMatter()
        failureDescriptions()
        contentRules()
        try await runnerRefusals()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try await extraction()
        if let directory = ProcessInfo.processInfo.environment["TINYCAST_WEBPAGE_TEST_DIRECTORY"] {
            try await files(URL(filePath: directory, directoryHint: .isDirectory))
        }
        if let directory = ProcessInfo.processInfo.environment["TINYCAST_WEBPAGE_LIVE_DIRECTORY"] {
            try await live(URL(filePath: directory, directoryHint: .isDirectory))
        }
        print("downloads-webpage: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func failureDescriptions() {
        let cases: [(WebpageExtractor.Failure, String)] = [
            (.inUse, "A webpage is already being saved."),
            (.unavailable(404), "The webpage returned HTTP status 404."),
            (.unsupportedContent, "This URL does not contain an HTML webpage."),
            (.blocked, "The webpage requires sign-in or a bot check."),
            (.noContent, "The webpage contains no readable article."),
            (.tooLarge, "The webpage is too large to save."),
            (.timedOut, "The webpage took too long to load."),
            (.renderFailed, "The webpage could not be rendered.")
        ]
        for (failure, expected) in cases {
            expect(failure.localizedDescription == expected, "queue detail: \(expected)")
        }
    }

    static func contentRules() {
        func blocked(_ url: String) -> Bool {
            WebpageWebViewConfiguration.blockedURLPatterns.contains {
                url.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
        for host in ["3dfx.de", "3abc.cafe", "0xff.example.com", "example.com"] {
            expect(!blocked("https://\(host)/"), "content rules allow hostname \(host)")
        }
        for host in ["127.0.0.1", "0x7f000001", "2130706433", "0177.1", "[::1]", "localhost"] {
            expect(blocked("https://\(host)/"), "content rules block literal or local host \(host)")
        }
    }

    static func runnerRefusals() async throws {
        let runner: any DownloadRunner = WebpageRunner()
        expect(runner.kind == "webpage" && runner.tools.isEmpty, "webpage runner needs no outside tools")
        let context = DownloadRunContext(destination: URL(filePath: "/unused-webpage-test-destination"))
        for source in ["file:///etc/passwd", "http://127.0.0.1/", "http://[::1]/"] {
            let job = DownloadJob(id: UUID().uuidString, kind: "webpage", source: source,
                                  title: "Refused", created: .now)
            do {
                _ = try await runner.run(job, context: context)
                expect(false, "runner refuses \(source)")
            } catch let error as PublicWebAddress.Refusal {
                expect(error.errorDescription?.isEmpty == false, "runner refusal has a clear detail")
            }
        }
    }

    static func converter() {
        expect(markdown("<h1>Title</h1><h2>Section</h2><h6>Small</h6>").contains("## Section"), "ATX headings")
        expect(markdown("<h6>Small</h6>") == "###### Small", "six heading levels")
        expect(markdown("<p>Hello <strong>bold</strong> and <em>italic</em>.</p>") == "Hello **bold** and *italic*.",
               "inline formatting preserves spaces")
        let list = markdown("<ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul><ol start='3'><li>Third</li></ol>")
        expect(list.contains("- One\n- Two"), "unordered list")
        expect(list.contains("  - Nested"), "nested list stays indented")
        expect(list.contains("3. Third"), "ordered list start")
        let links = markdown("<a href='../next?q=a&amp;b=c#part'>next</a> <a href='//cdn.example.com/x'>cdn</a>")
        expect(links.contains("[next](<https://example.com/next?q=a&b=c#part>)"), "relative link absolute with query")
        expect(links.contains("https://cdn.example.com/x"), "scheme-relative link")
        expect(markdown("<a href='javascript:alert(1)'>safe text</a>") == "safe text", "unsafe link dropped")
        expect(markdown("<a href='mailto:reader@example.com'>email</a>").contains("mailto:"), "email links retained")
        let code = markdown("<pre><code class='language-swift'>let x = 1\n\n  print(&quot;x&quot;)\n```</code></pre>")
        expect(code.hasPrefix("````swift\n"), "fence exceeds embedded backticks")
        expect(code.contains("\n\n  print(\"x\")"), "code whitespace preserved")
        expect(markdown("<p>Use <code>a`b</code>.</p>").contains("`` a`b ``"), "inline backtick delimiter")
        let table = markdown("<table><thead><tr><th>Name</th><th>Value</th></tr></thead><tbody>" +
                             "<tr><td>A|B</td><td><a href='/value'>read</a></td></tr></tbody></table>")
        expect(table.contains("| Name | Value |\n| --- | --- |"), "pipe table header")
        expect(table.contains("A\\|B") && table.contains("https://example.com/value"), "pipe cells and links")
        let image = markdown("<figure><img alt='A [photo]' src='/images/photo.png'><figcaption>Caption</figcaption></figure>")
        expect(image.contains("![A \\[photo\\]](<https://example.com/images/photo.png>)"), "remote image and alt")
        expect(image.contains("Caption"), "image caption retained")
        expect(markdown("<img src='data:image/png;base64,AA' data-src='../real.jpg'>").contains("https://example.com/real.jpg"),
               "lazy image source")
        expect(markdown("<img src='file:///tmp/photo.png'>").isEmpty, "local image source dropped")
        let clean = markdown("<nav>navigation</nav><script>if (a < b) alert('secret')</script><style>style</style>" +
                             "<main><p>Article</p><p hidden>hidden</p><p aria-hidden='true'>invisible</p></main>" +
                             "<footer>footer</footer><aside>related</aside>")
        expect(clean == "Article", "scripts and page chrome dropped")
        expect(markdown("<!-- <h1>comment</h1> --><p>A &amp; B &#169; &#x1F600; &mdash;</p>") == "A & B © 😀 —",
               "comments and entities")
        expect(markdown("<p>one<li>two<li>three").contains("three"), "tolerates unclosed HTML")
        expect(markdown("<blockquote><p>Quoted</p></blockquote>").contains("> Quoted"), "blockquote")
        expect(markdown("<p>Literal *stars* [brackets]</p>") == "Literal \\*stars\\* \\[brackets\\]", "Markdown escaping")
        expect(markdown("<p title='1 > 0'>kept</p>") == "kept", "quoted attribute greater-than")
        expect(markdown("<img alt=\"\" src=\"/empty-alt.png\">").contains("empty-alt.png"), "empty quoted attribute")
        expect(markdown("<h2>Heading<a href='#heading'><svg></svg></a></h2>") == "## Heading", "empty permalink dropped")
        expect(markdown("<main>\n <p>One</p>\n <p>Two</p>\n </main>") == "One\n\nTwo", "block whitespace normalized")
    }

    static func addresses() {
        for address in ["127.0.0.1", "0.0.0.0", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254",
                        "100.64.0.1", "192.0.2.1", "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1",
                        "255.255.255.255", "::", "::1", "fc00::1", "fe80::1", "::ffff:127.0.0.1",
                        "2001:db8::1", "2002:7f00:1::", "64:ff9b::7f00:1", "3fff::1"] {
            expect(!PublicWebAddress.isPublicIP(address), "refuses \(address)")
        }
        for address in ["8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:4700:4700::1111"] {
            expect(PublicWebAddress.isPublicIP(address), "permits \(address)")
        }
        for value in ["file:///etc/passwd", "ftp://example.com/a", "http://localhost/", "http://printer.local/",
                      "http://127.0.0.1/", "http://[::1]/", "http://2130706433/", "http://0x7f000001/",
                      "http://0177.0.0.1/", "http://user:pass@example.com/", "https://example.com:8443/"] {
            let accepted = URL(string: value).map { (try? PublicWebAddress.validate($0)) != nil } ?? false
            expect(!accepted, "refuses URL \(value)")
        }
        expect((try? PublicWebAddress.validate(base)) != nil, "permits public hostname")
    }

    static func article(title: String = "A title") -> WebpageArticle {
        WebpageArticle(title: title, author: "Example", published: "2026-10-30T12:00:00Z", source: base, baseURL: base,
                       html: "<h1>\(title)</h1><p>A useful article.</p>")
    }

    static func frontMatter() {
        let text = article().markdown(saved: Date(timeIntervalSince1970: 0))
        expect(text.hasPrefix("---\ntitle: \"A title\"\nauthor: \"Example\"\nsource:"), "front matter keys")
        expect(text.contains("published: 2026-10-30\nsaved: 1970-01-01\ntype: article\n---"), "published and injected saved date")
        expect(text.components(separatedBy: "# A title").count == 2, "does not duplicate article heading")
        let dangerous = article(title: "A \"quote\"\nsource: forged")
        expect(dangerous.markdown(saved: .distantPast).contains("\\nsource: forged\""), "YAML metadata escaped")
        expect(!article(title: "a/b:c?d").filename.contains("/"), "safe filename")
        expect(article(title: String(repeating: "😀", count: 150)).filename.utf8.count <= 200, "filename byte budget")
    }

    static func extraction() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        let navigation = FixtureNavigation()
        view.navigationDelegate = navigation
        let html = """
        <html><head><title>A useful headline for readers | Example</title>
        <meta property="og:title" content="Generic site title"><meta name="author" content="A Writer">
        <script type="application/ld+json">{"@graph":[{"datePublished":"2026-10-29"}]}</script></head>
        <body><main><header class="site-navigation"><h1>Site logo</h1><nav>navigation</nav></header>
        <article><h1>A useful headline for readers</h1><p>Article payload.</p>
        <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAUEBA==" data-src="/photo.jpg"></article>
        <footer>footer</footer><div>Other content</div></main></body></html>
        """
        try await navigation.load(html, into: view)
        let value = try await view.callAsyncJavaScript(WebpageExtraction.script, arguments: [:],
                                                       in: nil, contentWorld: .defaultClient)
        let data = Data((value as? String ?? "{}").utf8)
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let extracted = fields["html"] as? String ?? ""
        expect(fields["title"] as? String == "A useful headline for readers",
               "extractor prefers headline matching document title")
        expect(fields["author"] as? String == "A Writer" && fields["published"] as? String == "2026-10-29",
               "extractor metadata and JSON-LD")
        expect(extracted.contains("Article payload"), "extractor selects article")
        expect(!extracted.contains("navigation") && !extracted.contains("footer"),
               "extractor removes chrome")
        expect(extracted.contains("/photo.jpg"), "extractor retains remote images")
        view.navigationDelegate = nil
        view.stopLoading()
        let proxy = try PublicWebProxy()
        let proxyConfiguration = try await proxy.start()
        defer { proxy.stop() }
        let probe = try LoopbackProbe()
        let privateURL = try await probe.start()
        defer { probe.stop() }
        expect((try? PublicWebAddress.validate(privateURL)) == nil, "refuses loopback navigation")
        let guardedConfiguration = try await WebpageWebViewConfiguration.make(proxy: proxyConfiguration)
        let guardedView = WKWebView(frame: .zero, configuration: guardedConfiguration)
        let guardedNavigation = FixtureNavigation()
        guardedView.navigationDelegate = guardedNavigation
        let malicious = "<html><body><p>Public fixture</p><img src='\(privateURL.absoluteString)'>" +
            "<iframe src='\(privateURL.absoluteString)'></iframe></body></html>"
        try await guardedNavigation.load(malicious, into: guardedView, baseURL: URL(string: "http://example.com")!)
        expect(probe.connections == 0, "WebKit subresources cannot bypass public-address proxy")
        guardedView.stopLoading()
        guardedView.navigationDelegate = nil
    }

    @MainActor
    final class LoopbackProbe {
        let listener: NWListener
        var connections = 0
        var pending: CheckedContinuation<URL, any Error>?

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        func start() async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, let pending = self.pending else { return }
                        if case .ready = state, let port = self.listener.port {
                            self.pending = nil
                            pending.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/")!)
                        } else if case .failed(let error) = state {
                            self.pending = nil
                            pending.resume(throwing: error)
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        self?.connections += 1
                        connection.start(queue: .main)
                        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    }
                }
                listener.start(queue: .main)
            }
        }

        func stop() { listener.cancel() }
    }

    @MainActor
    final class FixtureNavigation: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, any Error>?

        func load(_ html: String, into view: WKWebView, baseURL: URL = DownloadsWebpageTests.base) async throws {
            try await withCheckedThrowingContinuation { pending in
                continuation = pending
                view.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    static func files(_ directory: URL) async throws {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let saver = WebpageSaver(destination: folder)
        let first = try await saver.write(article(), saved: .now)
        let before = try Data(contentsOf: first)
        let second = try await saver.write(article(), saved: .now)
        expect(first != second && second.lastPathComponent.hasSuffix(" (2).md"), "duplicate output gets unique name")
        let after = try Data(contentsOf: first)
        expect(after == before, "existing output preserved")
        let task = Task { try await saver.write(article(title: "Cancelled"), saved: .now) }
        task.cancel()
        do { _ = try await task.value; expect(false, "cancelled save throws") } catch is CancellationError {
            expect(true, "cancelled save throws")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        expect(!names.contains(where: { $0.hasPrefix(".") }), "staging files cleaned")
    }

    static func live(_ directory: URL) async throws {
        let saver = WebpageSaver(destination: directory)
        for value in ["https://example.com", "https://www.swift.org/blog/announcing-swift-6/"] {
            let output = try await saver.save(URL(string: value)!)
            let text = try String(contentsOf: output, encoding: .utf8)
            expect(!text.isEmpty && text.contains("source:"), "live saved \(value)")
            print("LIVE \(output.path)\n" + text.components(separatedBy: "\n").prefix(15).joined(separator: "\n"))
        }
    }
}
