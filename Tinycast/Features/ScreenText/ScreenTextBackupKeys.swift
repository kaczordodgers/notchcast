import Foundation

extension NotchcastFeature.BackupKeys {
    static let screenText = Self(allowed: [
        ScreenTextModule.removeLineBreaksKey: .bool,
    ], excluded: [], snapshot: {
        [ScreenTextModule.removeLineBreaksKey: ScreenTextModule.shared.removeLineBreaks]
    }, apply: { values in
        if let value = values[ScreenTextModule.removeLineBreaksKey] as? Bool { ScreenTextModule.shared.removeLineBreaks = value }
    })
}
