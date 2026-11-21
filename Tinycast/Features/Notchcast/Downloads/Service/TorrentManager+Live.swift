import AppKit
import Darwin
import UniformTypeIdentifiers

extension TorrentManager.Environment {
    /// The real Mac: aria2c from the user's own install, state in the add-on's private folder.
    static func live(downloads: URL, tools: DownloadToolLookup) -> Self {
        let state = AppPaths.applicationSupport().appending(path: "Notchcast/Torrents", directoryHint: .isDirectory)
        let tools = tools.withOwnChildren()
        return Self(
            downloads: downloads,
            startSession: { extra in
                try await Aria2Session.start(tools: tools, downloads: downloads, state: state, extra: extra)
            },
            read: { try await TorrentFileReader.read($0) },
            quarantine: TorrentFileReader.quarantine,
            pick: TorrentFileReader.pick,
            reveal: { NSWorkspace.shared.activateFileViewerSelecting($0) })
    }
}

/// Reads `.torrent` files under the size cap and marks finished files as downloaded.
nonisolated enum TorrentFileReader {
    @concurrent
    static func read(_ input: TorrentInput) async throws -> Data {
        let limit = TorrentMetainfo.maxBytes
        switch input {
        case .magnet:
            throw CocoaError(.fileReadUnsupportedScheme)
        case .file(let url):
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max <= limit else {
                throw CocoaError(.fileReadTooLarge)
            }
            return try Data(contentsOf: url)
        case .remote(let url):
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                  response.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { throw CocoaError(.fileReadTooLarge) }
            }
            return data
        }
    }

    /// The same mark a browser leaves, so Gatekeeper treats the files like any download.
    static func quarantine(_ files: [URL]) {
        let value = String(format: "0083;%08x;Notchcast;", Int(Date().timeIntervalSince1970))
        for file in files {
            _ = value.withCString { setxattr(file.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        }
    }

    /// The multi-select Open panel for `.torrent` files.
    @MainActor
    static func pick() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        // Activation is only a request, so at the normal level the panel can open behind Finder.
        panel.level = .modalPanel
        NSApp.activate()
        return panel.runModal() == .OK ? panel.urls : []
    }
}
