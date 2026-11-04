import Foundation
import Observation

@MainActor
@Observable
final class KatanaToneStore {
    private(set) var tones: [KatanaTone] = []
    private(set) var isBusy = false
    @ObservationIgnored private let file: URL

    init(file: URL) { self.file = file }

    func refresh() async throws {
        guard !isBusy else { throw KatanaError.busy }
        isBusy = true
        defer { isBusy = false }
        let tones = try await KatanaToneRepository.load(from: file)
        try Task.checkCancellation()
        self.tones = tones
    }

    func importFiles(_ urls: [URL]) async throws {
        guard !isBusy else { throw KatanaError.busy }
        isBusy = true
        defer { isBusy = false }
        let tones = try await KatanaToneRepository.importFiles(urls, into: file)
        try Task.checkCancellation()
        self.tones = tones
    }
}
