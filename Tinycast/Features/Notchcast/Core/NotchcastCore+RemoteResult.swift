extension NotchcastCore {
    // The user asked for this outcome, so the HUD shows it whenever the island would not.
    static func remoteResult(_ text: String) {
        AppCore.shared.showMessage(text, tone: .neutral)
    }
}
