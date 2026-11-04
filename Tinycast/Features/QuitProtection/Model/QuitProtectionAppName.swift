import Foundation

enum QuitProtectionAppName {
    static func displayName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
