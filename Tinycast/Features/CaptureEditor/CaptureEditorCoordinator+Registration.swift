extension CaptureEditorCoordinator: NotchcastRegistrant {
    static let shared = CaptureEditorCoordinator(reportFailure: {
        NotchcastHost.current.showMessage($0.localizedDescription, .danger)
    })

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        CaptureEditorWindowController.shared.attach(to: shared)
        return [.init(requires: [.captureEditor], module: shared)]
    }
}
