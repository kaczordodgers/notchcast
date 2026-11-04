import Foundation
import Observation

@MainActor
@Observable
final class DistillQueue {
    private struct Snapshot: Codable {
        var links: [DistillLink] = []
        var importedSources: Set<String> = []
    }

    private(set) var links: [DistillLink]
    @ObservationIgnored private var snapshot: Snapshot
    private let file: URL

    init(file: URL) throws {
        self.file = file
        let snapshot = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file)) : Snapshot()
        self.snapshot = snapshot
        links = snapshot.links
    }

    @discardableResult
    func add(text: String, now: Date) throws -> [DistillLink] {
        var candidate = snapshot
        var keys = Set(links.map { LinkCleaner.key($0.url) })
        let added = LinkCleaner.links(in: text).filter { keys.insert(LinkCleaner.key($0)).inserted }
            .map { DistillLink(url: $0, added: now) }
        guard !added.isEmpty else { return [] }
        candidate.links += added
        try commit(candidate)
        return added
    }

    func remove(_ id: UUID) throws {
        var candidate = snapshot
        candidate.links.removeAll { $0.id == id }
        try commit(candidate)
    }

    func retry(_ id: UUID) throws {
        guard let index = links.firstIndex(where: { $0.id == id && $0.state == .failed }) else { return }
        var candidate = snapshot
        candidate.links[index].state = .waiting
        candidate.links[index].detail = nil
        try commit(candidate)
    }

    func fail(_ id: UUID, detail: String) throws {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        var candidate = snapshot
        candidate.links[index].state = .failed
        candidate.links[index].detail = detail
        candidate.links[index].attempts += 1
        try commit(candidate)
    }

    @discardableResult
    func importLegacy(from source: URL, now: Date) throws -> Int {
        let key = source.standardizedFileURL.path
        guard !snapshot.importedSources.contains(key), FileManager.default.fileExists(atPath: key) else { return 0 }
        let old = try LegacyDistillQueue.parse(Data(contentsOf: source), now: now)
        var candidate = snapshot
        var keys = Set(links.map { LinkCleaner.key($0.url) })
        let added = old.filter { keys.insert(LinkCleaner.key($0.url)).inserted }
        candidate.links += added
        candidate.importedSources.insert(key)
        try commit(candidate)
        return added.count
    }

    private func commit(_ candidate: Snapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(candidate).write(to: file, options: .atomic)
        snapshot = candidate
        links = candidate.links
    }
}
