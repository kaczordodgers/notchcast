// notchcast-sources: Tinycast/Features/PasteTools/Model/*.swift
import Foundation

@main
struct PasteToolsPolicyTest {
    static func main() {
        precondition(PasteImagePolicy.accepts(types: ["public.png"]))
        precondition(!PasteImagePolicy.accepts(types: ["public.png", "public.file-url"]))
        precondition(!PasteImagePolicy.accepts(types: ["public.utf8-plain-text"]))
        print("✓ PasteTools: image eligibility and file precedence checks passed")
    }
}
