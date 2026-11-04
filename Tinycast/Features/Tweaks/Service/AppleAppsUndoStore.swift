import Foundation
import Observation

@MainActor
@Observable
final class AppleAppsUndoStore {
    struct Receipt: Codable, Equatable {
        var dock: Data?
        var music: Data?
    }

    private(set) var receipt: Receipt
    private let readDock: () throws -> Data
    private let writeDock: (Data) throws -> Void
    private let readMusic: () throws -> Data
    private let disableMusic: () throws -> Void
    private let restoreMusic: (Data) throws -> Void
    private let save: (Receipt) throws -> Void

    init(receipt: Receipt = .init(), readDock: @escaping () throws -> Data,
         writeDock: @escaping (Data) throws -> Void, readMusic: @escaping () throws -> Data,
         disableMusic: @escaping () throws -> Void, restoreMusic: @escaping (Data) throws -> Void,
         save: @escaping (Receipt) throws -> Void) {
        self.receipt = receipt
        self.readDock = readDock
        self.writeDock = writeDock
        self.readMusic = readMusic
        self.disableMusic = disableMusic
        self.restoreMusic = restoreMusic
        self.save = save
    }

    func setDock(_ on: Bool) throws {
        if on {
            guard receipt.dock == nil else { return }
            let plan = try AppleAppsPolicy.dockPlan(previous: readDock())
            var next = receipt
            next.dock = plan.previous
            try persist(next)
            try writeDock(plan.replacement)
        } else if let previous = receipt.dock {
            try writeDock(AppleAppsPolicy.restoreDock(previous: previous, current: readDock()))
            var next = receipt
            next.dock = nil
            try persist(next)
        }
    }

    func setMusic(_ on: Bool) throws {
        if on {
            guard receipt.music == nil else { return }
            var next = receipt
            next.music = try readMusic()
            try persist(next)
            try disableMusic()
        } else if let previous = receipt.music {
            try restoreMusic(previous)
            var next = receipt
            next.music = nil
            try persist(next)
        }
    }

    func stop() throws {
        try setDock(false)
        try setMusic(false)
    }

    private func persist(_ next: Receipt) throws {
        try save(next)
        receipt = next
    }
}
