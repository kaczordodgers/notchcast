import Foundation

enum SettingsTab: Sendable { case notchcast, notchcastMusicAndSound, notchcastTwoMacs }

struct AppEntry: Sendable {
    enum Kind: Sendable { case command }
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    let settingsOwner: SettingsTab?
    let symbolName: String?
}
