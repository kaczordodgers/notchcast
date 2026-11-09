extension NotchcastCore {
    static func remoteNotice(_ text: String) {
        deliverRemoteNotice(text, preferences: .shared) { IslandHUDRouter.post($0) }
    }

    static func deliverRemoteNotice(_ text: String, preferences: NotchcastPreferences, post: (String) -> Void) {
        guard preferences.isOn(.islandStatusMessages) else { return }
        post(text)
    }
}
