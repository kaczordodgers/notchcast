extension NotchcastCore {
    // The user asked for this outcome, so the HUD shows it whenever no island presenter would.
    static func remoteResult(_ text: String) {
        if IslandHUDRouter.post(text) == nil { AppCore.shared.showMessage(text, tone: .neutral) }
    }
}
