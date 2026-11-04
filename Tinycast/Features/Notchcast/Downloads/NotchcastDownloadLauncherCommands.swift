import Foundation
import Observation

@MainActor
enum NotchcastDownloadLauncherCommands {
    static weak var downloads: DownloadsModule?
    static weak var distill: DistillModule?

    static func trackAvailability(_ core: AppCore) {
        withObservationTracking {
            for feature in [NotchcastFeature.downloads, .distill, .distillConvert] {
                _ = NotchcastPreferences.shared.isOn(feature)
            }
        } onChange: { [weak core] in
            Task { @MainActor [weak core] in
                guard let core else { return }
                core.appIndex.refreshNotchcastCommands()
                trackAvailability(core)
            }
        }
    }

    nonisolated static let video = NotchcastCommand(
        slug: "download-video", name: String(localized: "Download Video"),
        sfSymbol: "video", owner: .notchcast,
        isEnabled: { isEnabled(.video) }, run: { perform(.video) })

    nonisolated static let audio = NotchcastCommand(
        slug: "download-audio", name: String(localized: "Download Audio"),
        sfSymbol: "waveform", owner: .notchcast,
        isEnabled: { isEnabled(.audio) }, run: { perform(.audio) })

    nonisolated static let transcript = NotchcastCommand(
        slug: "download-youtube-transcript", name: String(localized: "Download YouTube Transcript"),
        sfSymbol: "text.bubble", owner: .notchcast,
        isEnabled: { isEnabled(.transcript) }, run: { perform(.transcript) })

    nonisolated static let webpage = NotchcastCommand(
        slug: "save-webpage-as-markdown", name: String(localized: "Save Webpage as Markdown"),
        sfSymbol: "doc.text", owner: .notchcast,
        isEnabled: { isEnabled(.webpage) }, run: { perform(.webpage) })

    nonisolated static let addDistill = NotchcastCommand(
        slug: "add-links-to-distill", name: String(localized: "Add Links to Distill"),
        sfSymbol: "text.badge.plus", owner: .notchcast,
        isEnabled: { isEnabled(.addDistill) }, run: { perform(.addDistill) })

    nonisolated static let runDistill = NotchcastCommand(
        slug: "run-distill", name: String(localized: "Run Distill"),
        sfSymbol: "play", owner: .notchcast,
        isEnabled: { isEnabled(.runDistill) }, run: { perform(.runDistill) })

    nonisolated static let convert = NotchcastCommand(
        slug: "convert-distill-folder", name: String(localized: "Convert Distill Folder"),
        sfSymbol: "doc.on.doc", owner: .notchcast,
        isEnabled: { isEnabled(.convert) }, run: { perform(.convert) })

    nonisolated static let openDownloads = NotchcastCommand(
        slug: "open-downloads-folder", name: String(localized: "Open Downloads Folder"),
        sfSymbol: "folder", owner: .notchcast,
        isEnabled: { isEnabled(.openDownloads) }, run: { perform(.openDownloads) })

    nonisolated static let openDistill = NotchcastCommand(
        slug: "open-distill-folder", name: String(localized: "Open Distill Folder"),
        sfSymbol: "folder", owner: .notchcast,
        isEnabled: { isEnabled(.openDistill) }, run: { perform(.openDistill) })

    static func isEnabled(_ action: NotchcastDownloadCommands.Action) -> Bool {
        let preferences = NotchcastPreferences.shared
        return preferences.isOn(action.requiredFeature) && (!action.usesDistill || preferences.isOn(.distill))
    }

    private static func perform(_ action: NotchcastDownloadCommands.Action) {
        guard isEnabled(action), let downloads, let distill else { return }
        let commands = NotchcastDownloadCommands(downloads: downloads, distill: distill, preferences: .shared,
            status: { AppCore.shared.showMessage($0, tone: .danger) })
        if action.usesDistill {
            distill.commandTask?.cancel()
            distill.commandTask = Task { await commands.perform(action) }
        } else {
            downloads.commandTask?.cancel()
            downloads.commandTask = Task { await commands.perform(action) }
        }
    }
}
