// notchcast-sources: Tinycast/Features/URLCleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/URLCleaner/Service/URLCleanerModule.swift
// notchcast-sources: Tinycast/Features/Distill/Model/LinkCleaner.swift
import Foundation

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor final class FakePasteboard: URLCleanerPasteboard {
    var changeCount = 1
    var text: String? = "https://example.com/?utm_source=test"
    var isProtected = false
    var writes = 0
    func write(_ text: String) -> Bool {
        self.text = text
        changeCount += 1
        writes += 1
        return true
    }
}

@main struct Tests {
    @MainActor static func main() {
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
        print("URL Cleaner passed")
    }
}
