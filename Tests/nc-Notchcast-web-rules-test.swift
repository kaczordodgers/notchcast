// notchcast-sources: Tinycast/Features/Notchcast/Model/WebRules.swift
// notchcast-sources: Tinycast/Features/Distill/Model/LinkCleaner.swift Tinycast/Features/URLCleaner/Model/URLCleanerPolicy.swift
import CryptoKit
import Foundation

@main struct Tests {
    static func main() throws {
        for scheme in ["http", "https", "HTTP", "Https"] { assert(WebRules.isWebScheme(scheme)) }
        for scheme in [nil, "", "ftp", "file", "magnet", "httpx", "t3-thread"] { assert(!WebRules.isWebScheme(scheme)) }
        assert(WebRules.isWebScheme(URL(string: "HTTPS://example.com/#frag")?.scheme))

        for host in ["127.0.0.1", "localhost", "LocalHost", "::1"] { assert(WebRules.isLoopbackHost(host)) }
        for host in [nil, "", "127.0.0.2", "localhost.evil.com", "example.com", "0.0.0.0", "::2", "[::1]", "[127.0.0.1]"] {
            assert(!WebRules.isLoopbackHost(host))
        }
        assert(WebRules.isLoopbackHost(URL(string: "http://[::1]:8080/")?.host))

        for name in ["utm_source", "UTM_Campaign", "fbclid", "GCLID", "ttclid", "igsh", "ref_url", "spm", "_ga", "mkt_tok"] {
            assert(WebRules.isTrackingParameter(name))
        }
        for name in ["", "q", "v", "list", "utm", "xutm_source", "ref", "id"] { assert(!WebRules.isTrackingParameter(name)) }

        // The three cleaners share the one list: each strips what only the other used to.
        assert(WebRules.cleanLink("HTTPS://e.com/a?ttclid=1&igsh=2&spm=3&q=1#f") == "HTTPS://e.com/a?q=1#f")
        assert(WebRules.cleanLink("https://e.com/?") == "https://e.com/?")
        assert(WebRules.cleanLink("ftp://e.com/?utm_a=1") == nil)
        assert(LinkCleaner.clean("https://e.com/a?_ga=1&mkt_tok=2&q=2#frag") == "https://e.com/a?q=2")
        assert(LinkCleaner.clean("https://e.com/?") == "https://e.com")
        assert(URLCleanerPolicy.clean("https://e.com/?ref_url=1&vero_id=2&q=2#f").text == "https://e.com/?q=2#f")
        assert(URLCleanerPolicy.clean("https://e.com/?#f").removed.isEmpty)

        assert(WebRules.hex([UInt8]()) == "")
        assert(WebRules.hex([0, 1, 15, 16, 255]) == "00010f10ff")
        assert(WebRules.hex(SHA256.hash(data: Data("abc".utf8)))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        assert(WebRules.hex(Insecure.SHA1.hash(data: Data("abc".utf8))) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        assert(WebRules.hex(SHA256.hash(data: Data()).prefix(2)) == "e3b0")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("webrules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let attribute = "com.apple.quarantine"
        assert(getxattr(file.path, attribute, nil, 0, 0, 0) < 0)
        assert(WebRules.stampQuarantine(file.path, now: Date(timeIntervalSince1970: 255)) == 0)
        assert(value(of: attribute, at: file.path) == "0083;ff;Notchcast;")
        assert(WebRules.stampQuarantine(file.path, onlyIfMissing: true, now: Date(timeIntervalSince1970: 4096)) == 0)
        assert(value(of: attribute, at: file.path) == "0083;ff;Notchcast;")
        assert(WebRules.stampQuarantine(file.path, now: Date(timeIntervalSince1970: 4096)) == 0)
        assert(value(of: attribute, at: file.path) == "0083;1000;Notchcast;")
        assert(WebRules.stampQuarantine(folder.appendingPathComponent("missing").path) == ENOENT)
        assert(WebRules.stampQuarantine(folder.appendingPathComponent("missing").path, onlyIfMissing: true) == ENOENT)
        print("Web rules passed")
    }

    static func value(of attribute: String, at path: String) -> String? {
        let size = getxattr(path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(path, attribute, &bytes, size, 0, 0) == size else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }
}
