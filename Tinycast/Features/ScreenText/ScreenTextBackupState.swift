extension NotchcastBackupState {
    static let screenText = Self(snapshot: {
        ["screenText.removeLineBreaks": ScreenTextModule.shared.removeLineBreaks]
    }, apply: { values in
        if let value = values["screenText.removeLineBreaks"] as? Bool { ScreenTextModule.shared.removeLineBreaks = value }
    })
}
