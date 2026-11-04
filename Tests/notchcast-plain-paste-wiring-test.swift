// notchcast-sources: -parse-as-library
import Foundation

@main struct PlainPasteWiringTest {
    static func main() throws {
        let source = try String(contentsOfFile:
            "Tinycast/Features/Notchcast/Core/NotchcastCore+Modules.swift", encoding: .utf8)
        precondition(source.components(separatedBy: "PlainPasteModule(clipboard:").count == 2,
            "Expected exactly one plain paste module construction")
        precondition(source.contains("self.pastePlain = plainPasteModule"))
        precondition(source.contains(".init(requires: [.pastePlain], module: plainPasteModule)"))
        print("PASS: one construction shared by core and controller entry (source-level)")
    }
}
