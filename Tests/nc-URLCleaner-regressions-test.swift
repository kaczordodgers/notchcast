// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/URLCleaner/Model/*.swift Tinycast/Features/URLCleaner/Service/*.swift
// notchcast-reads: Tinycast/Features/Clipboard/Service/ClipboardManager.swift
import AppKit

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor enum ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]
}

@MainActor final class FailingPasteboard: URLCleanerPasteboard {
    var changeCount = 1
    var text: String? = "https://example.com/?utm_source=test"
    var isProtected = false
    var writes = 0
    func write(_ text: String) -> Bool { writes += 1; return false }
}

@main struct URLCleanerRegressionTests {
    @MainActor static func main() throws {
        let suite = "URLCleanerTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken JSON".utf8), forKey: "urlCleaner.rules")
        let module = URLCleanerModule(defaults: defaults)
        assert(module.rules == .init())
        var draft = URLCleanerRulesDraft()
        draft.custom = " custom, OTHER "
        draft.disabled = " UTM_source, gclid "
        draft.sites = "example.com=site;unfinished.example"
        assert(draft.rules.disabled == ["utm_source", "gclid"])
        assert(draft.rules.perSite["unfinished.example"] == [])
        module.rules = draft.rules
        let restored = URLCleanerModule(defaults: defaults)
        assert(restored.rules == draft.rules)
        assert(URLCleanerRulesDraft(restored.rules).rules == draft.rules)
        assert(URLCleanerPolicy.clean("https://example.com/?utm_source=x&custom=y&site=z", rules: restored.rules).text
            == "https://example.com/?utm_source=x")
        print("PASS: malformed rows survive save/reload; corrupt JSON, disabled rules and persistence")

        let failing = FailingPasteboard()
        module.start()
        module.rules = .init()
        module.clipboardDidChange(failing)
        assert(failing.writes == 1 && module.lastClean == nil)
        assert(failing.text == "https://example.com/?utm_source=test")
        module.clipboardDidChange(failing)
        assert(failing.writes == 1)
        print("PASS: failed write leaves original text and no successful-clean report")

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let adapter = URLCleanerSystemPasteboard(board)
        let raw = "https://example.com/?utm_source=test&keep=1"
        func put(_ types: [NSPasteboard.PasteboardType], count: Int = 1) {
            board.clearContents()
            let items = (0..<count).map { _ in
                let item = NSPasteboardItem()
                item.setString(raw, forType: .string)
                for type in types { item.setData(Data(), forType: type) }
                return item
            }
            assert(board.writeObjects(items))
        }
        for type in ClipboardManager.sensitiveTypes.union([ClipboardManager.internalType, .png, .rtf]) {
            put([type])
            assert(adapter.isProtected)
            module.clipboardDidChange(adapter)
            assert(adapter.text == raw && !adapter.write("replacement"))
        }
        put([], count: 2)
        assert(adapter.isProtected && !adapter.write("replacement"))
        put([.URL, .init("public.url-name")])
        assert(!adapter.isProtected)
        module.clipboardDidChange(adapter)
        let historyText = board.string(forType: .string)
        assert(historyText == "https://example.com/?keep=1")
        assert(board.types?.contains(ClipboardManager.internalType) == true)
        assert(adapter.isProtected && !adapter.write("replacement"))
        print("PASS: real pasteboard protects secrets, internal, rich and multiple items; plain URL rewrites")

        let source = try String(contentsOfFile: "Tinycast/Features/Clipboard/Service/ClipboardManager.swift", encoding: .utf8)
        let hook = source.range(of: "        pasteboardDidChange?(pb)")!
        let capture = source.range(of: "        if let text = pb.string(forType: .string)")!
        assert(hook.upperBound < capture.lowerBound)
        assert(!source.contains("defer { pasteboardDidChange?(pb) }"))
        print("PASS: synchronous hook precedes history text read; history receives cleaned URL")
    }
}
