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
        slug: "download-video", name: String(localized: "Download Video", table: "Notchcast"),
        sfSymbol: "video", feature: NotchcastDownloadCommands.Action.video.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.video) }, run: { perform(.video) })

    nonisolated static let audio = NotchcastCommand(
        slug: "download-audio", name: String(localized: "Download Audio", table: "Notchcast"),
        sfSymbol: "waveform", feature: NotchcastDownloadCommands.Action.audio.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.audio) }, run: { perform(.audio) })

    nonisolated static let transcript = NotchcastCommand(
        slug: "download-youtube-transcript", name: String(localized: "Download YouTube Transcript", table: "Notchcast"),
        sfSymbol: "text.bubble", feature: NotchcastDownloadCommands.Action.transcript.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.transcript) }, run: { perform(.transcript) })

    nonisolated static let webpage = NotchcastCommand(
        slug: "save-webpage-as-markdown", name: String(localized: "Save Webpage as Markdown", table: "Notchcast"),
        sfSymbol: "doc.text", feature: NotchcastDownloadCommands.Action.webpage.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.webpage) }, run: { perform(.webpage) })

    nonisolated static let addDistill = NotchcastCommand(
        slug: "add-links-to-distill", name: String(localized: "Add Links to Distill", table: "Notchcast"),
        sfSymbol: "text.badge.plus", feature: NotchcastDownloadCommands.Action.addDistill.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.addDistill) }, run: { perform(.addDistill) })

    nonisolated static let runDistill = NotchcastCommand(
        slug: "run-distill", name: String(localized: "Run Distill", table: "Notchcast"),
        sfSymbol: "play", feature: NotchcastDownloadCommands.Action.runDistill.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.runDistill) }, run: { perform(.runDistill) })

    nonisolated static let convert = NotchcastCommand(
        slug: "convert-distill-folder", name: String(localized: "Convert Distill Folder", table: "Notchcast"),
        sfSymbol: "doc.on.doc", feature: NotchcastDownloadCommands.Action.convert.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.convert) }, run: { perform(.convert) })

    nonisolated static let openDownloads = NotchcastCommand(
        slug: "open-downloads-folder", name: String(localized: "Open Downloads Folder", table: "Notchcast"),
        sfSymbol: "folder", feature: NotchcastDownloadCommands.Action.openDownloads.requiredFeature, owner: .notchcast,
        isEnabled: { isEnabled(.openDownloads) }, run: { perform(.openDownloads) })

    nonisolated static let openDistill = NotchcastCommand(
        slug: "open-distill-folder", name: String(localized: "Open Distill Folder", table: "Notchcast"),
        sfSymbol: "folder", feature: NotchcastDownloadCommands.Action.openDistill.requiredFeature, owner: .notchcast,
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
