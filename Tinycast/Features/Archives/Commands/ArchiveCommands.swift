import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
enum ArchiveCommands {
    nonisolated static let extractCommand = NotchcastCommand(
        slug: "extract-archive", name: String(localized: "Extract Archive…"),
        sfSymbol: "archivebox", isEnabled: { enabled }, run: { openPanel() })
    nonisolated static let cancelCommand = NotchcastCommand(
        slug: "cancel-extractions", name: String(localized: "Cancel All Extractions"),
        sfSymbol: "xmark.circle", isEnabled: { enabled }, run: { cancelAll() })

    private static let availability = ArchiveCommandAvailability()
    static var enabled: Bool {
        _ = availability
        return NotchcastPreferences.shared.isEnabled(.archives)
    }

    static func submit(_ urls: [URL], to module: ArchiveModule) -> String? {
        guard enabled else { return nil }
        guard module.isRunning else { return String(localized: "The archive engine is not running.") }
        guard !urls.isEmpty else { return String(localized: "No archive was selected.") }
        var rejected = false
        for url in urls where !module.open(url) { rejected = true }
        return rejected ? String(localized: "The selected file is not a supported archive.") : nil
    }

    static func cancelAll(in module: ArchiveModule = NotchcastCore.archives) {
        guard enabled else { return }
        guard module.isRunning else {
            AppCore.shared.showMessage(String(localized: "The archive engine is not running."), tone: .danger)
            return
        }
        module.queue.stop()
    }

    private static func openPanel() {
        guard enabled else { return }
        guard NotchcastCore.archives.isRunning else {
            AppCore.shared.showMessage(String(localized: "The archive engine is not running."), tone: .danger)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ArchiveFormat.typeIdentifiers.map { UTType(importedAs: $0) }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK, enabled else { return }
            if let message = submit(panel.urls, to: NotchcastCore.archives) {
                AppCore.shared.showMessage(message, tone: .danger)
            }
        }
    }
}

@MainActor
private final class ArchiveCommandAvailability {
    private var previous: Bool?

    init() { observe() }

    private func observe() {
        withObservationTracking {
            let current = NotchcastPreferences.shared.isEnabled(.archives)
            if let previous, previous != current { AppCore.shared.appIndex.refreshNotchcastCommands() }
            previous = current
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}
