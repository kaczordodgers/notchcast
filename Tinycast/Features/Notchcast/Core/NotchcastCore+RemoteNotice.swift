extension NotchcastCore {
    static func remoteNotice(_ text: String) {
        deliverRemoteNotice(text, preferences: .shared) {
            IslandActivityCenter.shared.showMessage($0, tone: .neutral, dwell: Theme.Duration.messageHUD)
        }
    }

    static func deliverRemoteNotice(_ text: String, preferences: NotchcastPreferences, post: (String) -> Void) {
        guard preferences.isOn(.islandStatusMessages) else { return }
        post(text)
    }
}
