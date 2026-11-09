enum HideCommandMPolicy {
    static func shouldHide(pid: Int32, ownPID: Int32, isFinder: Bool, hasWindows: Bool) -> Bool {
        pid > 0 && pid != ownPID && (!isFinder || hasWindows)
    }
}
