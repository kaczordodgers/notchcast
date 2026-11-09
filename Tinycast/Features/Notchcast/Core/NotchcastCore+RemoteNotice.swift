extension NotchcastCore {
    static func remoteNotice(_ text: String) {
        IslandHUDRouter.post(text)
    }
}
