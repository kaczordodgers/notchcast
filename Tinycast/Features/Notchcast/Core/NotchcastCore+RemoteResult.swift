extension NotchcastCore {
    // The user asked for this outcome, so turning island messages off must not swallow it.
    static func remoteResult(_ text: String) {
        if NotchcastPreferences.shared.isOn(.islandStatusMessages) {
            remoteNotice(text)
        } else {
            AppCore.shared.showMessage(text, tone: .neutral)
        }
    }
}
