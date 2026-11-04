// notchcast-sources: Tinycast/Features/PasteTools/Model/*.swift
import Foundation

@main
struct PasteToolsPolicyTest {
    static func main() {
        precondition(PasteImagePolicy.accepts(types: ["public.png"]))
        precondition(!PasteImagePolicy.accepts(types: ["public.png", "public.file-url"]))
        precondition(!PasteImagePolicy.accepts(types: ["public.utf8-plain-text"]))
        var policy = PasteImagePolicy()
        precondition(policy.take(down: true, repeatKey: false, eligible: true))
        precondition(policy.take(down: true, repeatKey: true, eligible: false))
        precondition(policy.take(down: false, repeatKey: false, eligible: false))
        precondition(!policy.take(down: true, repeatKey: false, eligible: false))
        precondition(!policy.take(down: false, repeatKey: false, eligible: true))
        print("✓ PasteTools: image eligibility, file precedence, repeat and release checks passed")
    }
}
