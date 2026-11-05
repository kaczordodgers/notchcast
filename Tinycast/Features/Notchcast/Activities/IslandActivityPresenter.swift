enum IslandPresenterPolicy {
    static func shouldRegister(running: Bool, enabled: Bool, visibleOnActiveScreen: Bool) -> Bool {
        running && enabled && visibleOnActiveScreen
    }
}
