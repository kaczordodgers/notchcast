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
        MachRemoteModule.self,
        ShelfModule.self,
        RemoteFanModule.self,
        RemoteScreenModule.self,
        BlockedDialogModule.self,
        LinkQuickFixModule.self,
        TweaksModule.self,
        MonitorModule.self,
        BatteryModule.self,
        SystemNoticesModule.self,
        SystemLevelsModule.self,
        MusicNowPlayingModule.self,
        MicrophoneMuteModule.self,
        TodoModule.self,
    ]
}
