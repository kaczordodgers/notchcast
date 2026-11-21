// notchcast-addon-order: 80
// notchcast-readme: Downloads: video, audio, transcripts and webpages from clipboard links,
// notchcast-readme: Downloads: with optional aria2c and transcription into a local folder;
// notchcast-readme: Downloads: downloads and torrents can use Wi-Fi and a USB-tethered iPhone together;
// notchcast-readme: Downloads: optionally a copy of each note in a Markdown folder you choose,
// notchcast-readme: Downloads: where PDF, HTML, audio and video files added while the option is on become notes and their originals go to the Trash
// notchcast-new-switch-ids: downloadsUseIPhone
import Foundation

/// Saves copied links as video, audio, transcripts or Markdown, and distils them into one folder.
enum DownloadsAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "downloads",
            title: String(localized: "Downloads", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Download video, audio, transcripts and webpages from clipboard links.",
                table: "NotchcastDownloads"),
            category: .filesDownloads),
        NotchcastSwitch(
            id: "downloadsAria2",
            title: String(localized: "Fast Downloads with aria2c", table: "NotchcastDownloads"),
            subtitle: String(localized: "Media downloads only, when aria2c is installed.", table: "NotchcastDownloads"),
            category: .filesDownloads, dependencies: ["downloads"]),
        NotchcastSwitch(
            id: "distill",
            title: String(localized: "Distill", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Save links and transcribe media into ~/Downloads/Distill/Raw.", table: "NotchcastDownloads"),
            category: .filesDownloads),
        NotchcastSwitch(
            id: "distillTimestamps",
            title: String(localized: "Distill Timestamps", table: "NotchcastDownloads"),
            subtitle: String(localized: "Approximate, one per chunk.", table: "NotchcastDownloads"),
            category: .filesDownloads, dependencies: ["distill"]),
        NotchcastSwitch(
            id: "torrents",
            title: String(localized: "Torrents", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Default app for magnet links and .torrent files; downloads them to ~/Downloads with aria2c.",
                table: "NotchcastDownloads"),
            category: .filesDownloads),
        NotchcastSwitch(
            id: "torrentsKeepSharing",
            title: String(localized: "Keep sharing until ratio 1.0", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Upload as much as you downloaded before stopping. Off stops sharing once complete.",
                table: "NotchcastDownloads"),
            category: .filesDownloads, dependencies: ["torrents"]),
        NotchcastSwitch(
            id: "downloadsUseIPhone",
            title: String(localized: "Use Wi-Fi and a plugged-in iPhone together", table: "NotchcastDownloads"),
            subtitle: [
                String(
                    localized: "Torrents and Fast Downloads use both while the iPhone shares Personal Hotspot over USB.",
                    table: "NotchcastDownloads"),
                String(localized: "This uses mobile data.", table: "NotchcastDownloads"),
            ].joined(separator: " "),
            category: .filesDownloads),
    ]

    static let commands = DownloadsModule.Action.allCases.map { action in
        NotchcastCommand(
            slug: action.slug, name: action.name, symbol: action.symbol, switchID: action.switchID,
            keywords: action.keywords
        ) {
            $0.module(DownloadsModule.self)?.perform(action)
        }
    } + DownloadsModule.TorrentCommand.allCases.map { command in
        NotchcastCommand(
            slug: command.slug, name: command.name, symbol: command.symbol, switchID: DownloadsModule.torrentsSwitchID
        ) {
            $0.module(DownloadsModule.self)?.perform(command)
        }
    }

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        DownloadsModule(context: context, environment: .live())
    }

    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? {
        TorrentOpenFallback(context: context, system: .live())
    }
}

extension DownloadsModule.TorrentCommand {
    var slug: String {
        switch self {
        case .clipboard: "download-torrent-from-clipboard"
        case .file: "open-torrent-file"
        case .cancelAll: "cancel-all-torrents"
        }
    }

    var name: String {
        switch self {
        case .clipboard: String(localized: "Download Torrent from Clipboard", table: "NotchcastDownloads")
        case .file: String(localized: "Open Torrent File…", table: "NotchcastDownloads")
        case .cancelAll: String(localized: "Cancel All Torrents", table: "NotchcastDownloads")
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: "arrow.down.doc"
        case .file: "doc.badge.arrow.up"
        case .cancelAll: "xmark.circle"
        }
    }
}

extension DownloadsModule.Action {
    var slug: String {
        switch self {
        case .video: "download-video"
        case .audio: "download-audio"
        case .transcript: "download-youtube-transcript"
        case .webpage: "save-webpage-as-markdown"
        case .addDistill: "add-links-to-distill"
        case .runDistill: "run-distill"
        }
    }

    var name: String {
        switch self {
        case .video: String(localized: "Download Video", table: "NotchcastDownloads")
        case .audio: String(localized: "Download Audio", table: "NotchcastDownloads")
        case .transcript: String(localized: "Download Transcript", table: "NotchcastDownloads")
        case .webpage: String(localized: "Save Webpage as Markdown", table: "NotchcastDownloads")
        case .addDistill: String(localized: "Add Links to Distill", table: "NotchcastDownloads")
        case .runDistill: String(localized: "Run Distill", table: "NotchcastDownloads")
        }
    }

    /// Search words the name leaves out: a transcript comes from YouTube.
    var keywords: [String] { self == .transcript ? ["youtube"] : [] }

    var symbol: String {
        switch self {
        case .video: "video"
        case .audio: "waveform"
        case .transcript: "text.bubble"
        case .webpage: "doc.text"
        case .addDistill: "text.badge.plus"
        case .runDistill: "play"
        }
    }
}
