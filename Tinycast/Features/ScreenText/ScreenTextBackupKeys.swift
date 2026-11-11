import Foundation

extension NotchcastFeature.BackupKeys {
    static let screenText = Self(allowed: [
        "screenText.removeLineBreaks": .bool,
    ], excluded: [], snapshot: {
        ["screenText.removeLineBreaks": ScreenTextModule.shared.removeLineBreaks]
    }, apply: { values in
        if let value = values["screenText.removeLineBreaks"] as? Bool { ScreenTextModule.shared.removeLineBreaks = value }
    })
}
