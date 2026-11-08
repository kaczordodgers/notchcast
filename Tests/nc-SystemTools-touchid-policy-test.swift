// notchcast-sources: Tinycast/Features/SystemTools/Model/TouchIDPolicy.swift
import Foundation

@main
struct TouchIDTests {
    static func main() throws {
        let sudo = "auth include sudo_local\n"
        let rule = "auth       sufficient     pam_tid.so\n"
        var failures: [String] = []
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { failures.append(message) }
        }
        for original: String? in [nil, "", "# preserved\n", "auth required pam_other.so"] {
            let text = original ?? ""
            let expected = text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + rule
            let enabled: String? = try TouchIDPolicy.replacement(sudo: sudo, local: original, enabled: true)
            expect(enabled == expected, "PAM edit preserves helper spacing and unrelated rules")
            let repeated: String? = try TouchIDPolicy.replacement(sudo: sudo, local: enabled, enabled: true)
            expect(repeated == nil, "Already enabled returns no edit")
            let unchanged: String? = try TouchIDPolicy.replacement(sudo: sudo, local: original, enabled: false)
            expect(unchanged == nil, "Already disabled returns no edit without creating a file")
            let disabled: String? = try TouchIDPolicy.replacement(sudo: sudo, local: expected, enabled: false)
            expect(disabled == expected.replacingOccurrences(of: rule, with: ""), "Disable preserves unrelated rules")
        }
        let inline = "# keep\nauth sufficient pam_tid.so # active\nauth required pam_other.so\n"
        expect(try TouchIDPolicy.replacement(sudo: sudo, local: inline, enabled: false)
               == "# keep\nauth required pam_other.so\n", "Inline comments do not hide the active rule")
        for (system, local) in [("", ""), (sudo + rule, ""), (sudo, "auth required pam_tid.so\n")] {
            do {
                _ = try TouchIDPolicy.replacement(sudo: system, local: local, enabled: true)
                failures.append("Unsupported PAM configuration must be refused")
            } catch { checks += 1 }
        }
        for failure in failures { print("FAIL: \(failure)") }
        print("TouchID policy: \(checks - failures.count) passed, \(failures.count) failed")
        if !failures.isEmpty { exit(1) }
    }
}
