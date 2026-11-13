// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/URLCleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/URLCleaner/Service/*.swift
// notchcast-sources: Tinycast/Features/Distill/Model/LinkCleaner.swift
// notchcast-reads: Tinycast/Features/Clipboard/Service/ClipboardManager.swift
import AppKit

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor final class FakePasteboard: URLCleanerPasteboard {
    var changeCount = 1
    var text: String? = "https://example.com/?utm_source=test"
    var isProtected = false
    var writes = 0
    var writeSucceeds = true
    func write(_ text: String) -> Bool {
        writes += 1
        guard writeSucceeds else { return false }
        self.text = text
        changeCount += 1
        return true
    }
}

@main struct Tests {
    @MainActor static func main() throws {
        let raw = "HTTPS://Example.com:443/a%2fb?x=%2f+%20&utm_source=a%26b&x=2#F%2f"
        assert(URLCleanerPolicy.clean(raw).text == "HTTPS://Example.com:443/a%2fb?x=%2f+%20&x=2#F%2f")
        assert(URLCleanerPolicy.clean(raw).removed == ["utm_source=a%26b"])
        for name in ["fbclid", "gclid", "mc_eid", "UTM_campaign", "%75tm_source"] {
            assert(URLCleanerPolicy.clean("https://e.com/?\(name)=v#f").text == "https://e.com/#f")
        }
        for text in ["hello", "https://e.com/?x=%2f&&a=#f", "https://e.com/#f?utm_a=1",
                     " https://e.com/?utm_a=1", "https://e.com/?utm_a=1\n", "https://a.com https://b.com"] {
            assert(URLCleanerPolicy.clean(text).text == text)
        }
        let rules = URLCleanerPolicy.Rules(custom: ["custom"], perSite: ["e.com": ["site"]], disabled: ["gclid"])
        assert(URLCleanerPolicy.clean("https://e.com/?custom=1&site=2&gclid=3", rules: rules).text == "https://e.com/?gclid=3")
        assert(URLCleanerPolicy.clean("https://other.com/?site=2", rules: rules).removed.isEmpty)
        assert(LinkCleaner.clean("https://EXAMPLE.com/a/?utm_source=x&x=1#frag") == "https://example.com/a?x=1")
        assert(LinkCleaner.clean("https://youtu.be/abc?si=test") == "https://www.youtube.com/watch?v=abc")
        var draft = URLCleanerRulesDraft()
        draft.custom = "first,"
        draft.sites = "example.com="
        assert(draft.custom == "first," && draft.sites == "example.com=")
        draft.custom += "second"
        draft.sites += "one,two"
        assert(draft.rules.custom == ["first", "second"])
        assert(draft.rules.perSite == ["example.com": ["one", "two"]])
        draft.sites = "a.com=x; "
        assert(draft.rules.perSite == ["a.com": ["x"]])
        draft.sites = "a.com=x; b.com=y"
        assert(draft.rules.perSite == ["a.com": ["x"], "b.com": ["y"]])
        assert(URLCleanerPolicy.clean("https://b.com/?y=1&keep=2", rules: draft.rules).text == "https://b.com/?keep=2")
        let module = URLCleanerModule()
        let board = FakePasteboard()
        module.start()
        board.isProtected = true
        module.clipboardDidChange(board)
        assert(board.writes == 0)
        board.isProtected = false
        board.changeCount += 1
        module.clipboardDidChange(board)
        module.clipboardDidChange(board)
        assert(board.writes == 1 && module.lastClean?.removed == ["utm_source=test"])
        module.stop()
        board.changeCount += 1
        module.clipboardDidChange(board)
        assert(board.writes == 1)
        try regressions()
        print("URL Cleaner passed")
    }

    @MainActor static func regressions() throws {
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

        let failing = FakePasteboard()
        failing.writeSucceeds = false
        module.start()
        module.rules = .init()
        module.clipboardDidChange(failing)
        assert(failing.writes == 1 && module.lastClean == nil)
        module.clipboardDidChange(failing)
        assert(failing.writes == 1)
        print("PASS: failed write leaves no successful-clean report")

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let adapter = URLCleanerSystemPasteboard(board)
        let raw = "https://example.com/?utm_source=test&keep=1"
        func put(_ types: [NSPasteboard.PasteboardType], count: Int = 1) {
            board.clearContents()
            let items = (0..<count).map { _ in
                let item = NSPasteboardItem()
                item.setString(raw, forType: .string)
                for type in types { item.setString(raw, forType: type) }
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
        assert(!adapter.isProtected, "types=\(board.types ?? []), items=\(board.pasteboardItems?.map(\.types) ?? [])")
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

@MainActor enum ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]
}
