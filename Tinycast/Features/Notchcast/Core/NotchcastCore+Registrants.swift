/// One registrant per line, so branches that add features merge by union.
/// `notchcast/check-feature-shape.py` rejects a line a union merge kept twice.
extension NotchcastCore {
    static let registrants: [any NotchcastRegistrant.Type] = [
        LowDiskModule.self,
        WaitingAlertsModule.self,
        ColorPickerModule.self,
        ScreenshotModule.self,
        ScreenTextModule.self,
        ScrollingCaptureModule.self,
        CaptureTrimmerModule.self,
        CaptureEditorCoordinator.self,
        RecordingModule.self,
        KatanaModule.self,
        TreadmillCoordinator.self,
        AgentSessionsModule.self,
        OpenBotAgentsModule.self,
        AgentThreadsModule.self,
        AgentIslandModule.self,
        FleetPanelModule.self,
    ]
}
