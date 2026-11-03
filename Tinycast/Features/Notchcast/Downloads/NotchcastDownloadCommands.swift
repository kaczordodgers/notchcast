import AppKit

@MainActor
struct NotchcastDownloadCommands {
    struct Entry {
        let title: String
        let keywords: [String]
        let symbol: String
        let action: Action
    }

    enum Action: CaseIterable {
        case video, audio, transcript, webpage, addDistill, runDistill, convert, openDownloads, openDistill

        var requiredFeature: NotchcastFeature {
            switch self {
            case .video, .audio, .transcript, .webpage, .openDownloads: .downloads
            case .addDistill, .runDistill, .openDistill: .distill
            case .convert: .distillConvert
            }
        }

        var usesDistill: Bool {
            switch self {
            case .addDistill, .runDistill, .convert, .openDistill: true
            default: false
            }
        }
    }

    let downloads: DownloadsModule
    let distill: DistillModule
    let preferences: NotchcastPreferences
    var clipboard: () -> String = { NSPasteboard.general.string(forType: .string) ?? "" }
    var status: (String) -> Void = { _ in NSSound.beep() }
    var openFolder: (URL) throws -> Void = { folder in
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !NSWorkspace.shared.open(folder) { throw CocoaError(.fileReadUnknown) }
    }

    var entries: [Entry] { Self.catalog.filter { isEnabled($0.action) } }

    func perform(_ action: Action) async {
        guard isEnabled(action) else { return }
        let state = action.usesDistill ? distill.state : downloads.state
        await state.settle()
        guard !Task.isCancelled, isEnabled(action), let queue = state.queue else { return }
        do {
            switch action {
            case .openDownloads, .openDistill:
                try openFolder(state.destination)
            case .runDistill:
                try await distill.run()
            case .convert:
                distill.convert()
            case .video, .audio, .transcript, .webpage, .addDistill:
                let sources = Self.urls(in: clipboard())
                guard !sources.isEmpty else { status(String(localized: "No Web Links in Clipboard")); return }
                if action == .addDistill {
                    try distill.links?.add(text: sources.joined(separator: "\n"), now: .now)
                } else {
                    let kind: String
                    switch action {
                    case .video: kind = "video"
                    case .audio: kind = "audio"
                    case .transcript: kind = "transcript"
                    default: kind = "webpage"
                    }
                    queue.enqueue(kind: kind, sources: sources)
                }
            }
        } catch {
            status(error.localizedDescription)
        }
    }

    static func urls(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let url = match.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  text[range].lowercased().hasPrefix(scheme + "://"),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url.absoluteString
        }
    }

    private func isEnabled(_ action: Action) -> Bool {
        preferences.isOn(action.requiredFeature) && (!action.usesDistill || preferences.isOn(.distill))
    }

    private static var catalog: [Entry] {
        [
            .init(title: String(localized: "Download Video"), keywords: ["download video", "youtube", "media", "clipboard"],
                  symbol: "video", action: .video),
            .init(title: String(localized: "Download Audio"), keywords: ["download audio", "mp3", "music", "clipboard"],
                  symbol: "waveform", action: .audio),
            .init(title: String(localized: "Download YouTube Transcript"),
                  keywords: ["download youtube transcript", "captions", "subtitles", "text"],
                  symbol: "text.bubble", action: .transcript),
            .init(title: String(localized: "Save Webpage as Markdown"),
                  keywords: ["save webpage as markdown", "article", "html", "clipboard"],
                  symbol: "doc.text", action: .webpage),
            .init(title: String(localized: "Add Links to Distill"), keywords: ["add links to distill", "clipboard", "queue"],
                  symbol: "text.badge.plus", action: .addDistill),
            .init(title: String(localized: "Run Distill"), keywords: ["run distill", "transcribe", "queue", "start"],
                  symbol: "play", action: .runDistill),
            .init(title: String(localized: "Convert Distill Folder"),
                  keywords: ["convert distill folder", "markdown", "pdf", "ocr"],
                  symbol: "doc.on.doc", action: .convert),
            .init(title: String(localized: "Open Downloads Folder"), keywords: ["open downloads folder", "finder", "files"],
                  symbol: "folder", action: .openDownloads),
            .init(title: String(localized: "Open Distill Folder"),
                  keywords: ["open distill folder", "finder", "transcripts", "raw"],
                  symbol: "folder", action: .openDistill)
        ]
    }
}
