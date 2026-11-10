// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One lookup per browser track; covers stay in memory for the last few tracks, never on disk.
@MainActor
final class BrowserCoverFinder {
    typealias ReadSession = @Sendable (String) async -> BrowserCoverSession?
    typealias Fetch = @Sendable (URL, String) async -> Data?

    private struct Job {
        let id = UUID()
        let key: String
        let bundleID: String
        let title: String
        let artist: String?
        /// A session saved after this lists the tab of whatever plays now.
        let started: Date
    }

    var onFound: () -> Void = {}
    private let readSession: ReadSession
    private let fetch: Fetch
    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let country: String?
    private var covers: [String: Data] = [:]
    private var coverOrder: [String] = []
    private var failedAt: [String: Date] = [:]
    private var lookup: (job: Job, task: Task<Void, Never>)?

    init(readSession: @escaping ReadSession = { await BrowserCoverSources.readSession(bundleID: $0) },
         fetch: @escaping Fetch = { await BrowserCoverSources.fetch($0, accept: $1) },
         now: @escaping () -> Date = Date.init,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         country: String? = Locale.current.region?.identifier) {
        self.readSession = readSession
        self.fetch = fetch
        self.now = now
        self.sleep = sleep
        self.country = country
    }

    isolated deinit { lookup?.task.cancel() }

    /// The track with the cover found for it; a track still without one starts its lookup.
    func cover(for track: NowPlaying?) -> NowPlaying? {
        guard let track, let key = BrowserCoverRules.lookupKey(for: track), let bundleID = track.bundleID else {
            cancel()
            return track
        }
        if let cover = covers[key] {
            cancel()
            var covered = track
            covered.artwork = cover
            return covered
        }
        guard lookup?.job.key != key else { return track }
        cancel()
        if let failed = failedAt[key], now().timeIntervalSince(failed) < BrowserCoverRules.failureCooldown {
            return track
        }
        let job = Job(key: key, bundleID: bundleID, title: track.title,
                      artist: track.artist.isEmpty ? nil : track.artist, started: now())
        lookup = (job, Task { [weak self] in await self?.run(job) })
        return track
    }

    func reset() {
        cancel()
        covers = [:]
        coverOrder = []
        failedAt = [:]
    }

    private func cancel() {
        lookup?.task.cancel()
        lookup = nil
    }

    private func isCurrent(_ job: Job) -> Bool {
        !Task.isCancelled && lookup?.job.id == job.id
    }

    private func run(_ job: Job) async {
        var askedApple = false
        for delay in BrowserCoverRules.attemptDelays {
            do { try await sleep(delay) } catch { return }
            guard isCurrent(job) else { return }
            let session = await readSession(job.bundleID)
            guard isCurrent(job) else { return }
            let urls = BrowserCoverRules.artworkURLs(forTrack: job.title, artist: job.artist, in: session?.tabs ?? [])
            if !urls.isEmpty { return finish(job, with: await download(urls, for: job)) }
            guard !askedApple, let session,
                  BrowserCoverRules.asksAppleMusic(tabs: session.tabs, savedAt: session.savedAt, lookupStarted: job.started),
                  let search = BrowserCoverRules.appleMusicSearchURL(title: job.title, artist: job.artist, country: country)
            else { continue }
            askedApple = true
            let reply = await fetch(search, "application/json")
            guard isCurrent(job) else { return }
            if let reply,
               let art = BrowserCoverRules.appleMusicArtworkURL(inSearch: reply, title: job.title, artist: job.artist),
               let cover = await download([art], for: job) {
                return finish(job, with: cover)
            }
        }
        finish(job, with: nil)
    }

    /// The first address that answers with a real image, cropped to its centre square.
    private func download(_ urls: [URL], for job: Job) async -> Data? {
        for url in urls {
            guard isCurrent(job) else { return nil }
            guard let data = await fetch(url, "image/jpeg"), isCurrent(job) else { continue }
            if let square = await BrowserCoverSources.square(data) { return square }
        }
        return nil
    }

    private func finish(_ job: Job, with cover: Data?) {
        guard isCurrent(job) else { return }
        lookup = nil
        guard let cover else {
            let now = now()
            failedAt = failedAt.filter { now.timeIntervalSince($0.value) < BrowserCoverRules.failureCooldown }
            failedAt[job.key] = now
            return
        }
        covers[job.key] = cover
        coverOrder.removeAll { $0 == job.key }
        coverOrder.append(job.key)
        while coverOrder.count > BrowserCoverRules.rememberedCovers { covers[coverOrder.removeFirst()] = nil }
        onFound()
    }
}
