import AppKit

extension CaptureTrimmerModule {
    static func live() -> CaptureTrimmerModule {
        let folder = URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.notchcast.dev")
            .appendingPathComponent("Recordings", isDirectory: true)
        return CaptureTrimmerModule(workFolder: folder) { url in
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([url as NSURL]) else {
                throw CaptureTrimService.Failure.cannotWrite
            }
        }
    }
}
