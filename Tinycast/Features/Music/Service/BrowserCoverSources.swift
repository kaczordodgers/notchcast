// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct BrowserCoverSession: Sendable {
    let savedAt: Date
    let tabs: [BrowserCoverRules.SessionTab]
}

/// The lookup's effects: the browser's session file, read into memory only, and capped downloads.
enum BrowserCoverSources {
    /// The running profile keeps rewriting its recovery file, so the newest file is the one playing.
    @concurrent
    static func readSession(bundleID: String) async -> BrowserCoverSession? {
        guard let folder = BrowserCoverRules.profileFolders[bundleID] else { return nil }
        let root = URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
        let profiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let newest = profiles
            .flatMap { profile in BrowserCoverRules.sessionFiles.map { profile.appending(path: $0) } }
            .compactMap { file -> (url: URL, modified: Date, size: Int)? in
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let modified = values.contentModificationDate, let size = values.fileSize else { return nil }
                return (file, modified, size)
            }
            .max { $0.modified < $1.modified }
        guard let newest, newest.size <= BrowserCoverRules.maximumSessionFileBytes,
              let file = try? Data(contentsOf: newest.url), file.count <= BrowserCoverRules.maximumSessionFileBytes
        else { return nil }
        let tabs = autoreleasepool { () -> [BrowserCoverRules.SessionTab]? in
            BrowserCoverRules.decodeMozLZ4(file).map { BrowserCoverRules.youTubeTabs(BrowserCoverRules.openTabs(inSession: $0)) }
        }
        return tabs.map { BrowserCoverSession(savedAt: newest.modified, tabs: $0) }
    }

    /// Cookieless, credential-free and redirect-refusing, so a request only reaches the host it names.
    @concurrent
    static func fetch(_ url: URL, accept: String) async -> Data? {
        let configuration = NotchcastIdentity.sessionConfiguration()
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["Accept": accept]
        let session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.expectedContentLength <= BrowserCoverRules.maximumArtworkBytes else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < BrowserCoverRules.maximumArtworkBytes else { return nil }
                data.append(byte)
            }
            return data
        } catch {
            return nil
        }
    }

    @concurrent
    static func square(_ image: Data) async -> Data? {
        BrowserCoverRules.squareCover(image)
    }
}
