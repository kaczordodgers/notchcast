import AppKit

@MainActor
struct NotchcastDownloadCommands {
    let downloads: DownloadsModule
    let distill: DistillModule
    let preferences: NotchcastPreferences
    var clipboard: () -> String = { NSPasteboard.general.string(forType: .string) ?? "" }
    var status: (String) -> Void = { _ in NSSound.beep() }
    var openFolder: (URL) throws -> Void = { folder in
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !NSWorkspace.shared.open(folder) { throw CocoaError(.fileReadUnknown) }
    }

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
                guard !sources.isEmpty else { status(String(localized: "No Web Links in Clipboard", table: "Notchcast")); return }
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

    func isEnabled(_ action: Action) -> Bool {
        preferences.isOn(action.requiredFeature) && (!action.usesDistill || preferences.isOn(.distill))
    }

}
