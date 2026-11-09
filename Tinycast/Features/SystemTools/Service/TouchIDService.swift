import Foundation

nonisolated struct TouchIDService: Sendable {
    struct Reading: Sendable, Equatable {
        let sudo: String
        let local: String?
        var enabled: Bool { TouchIDPolicy.enabled(in: sudo) || TouchIDPolicy.enabled(in: local ?? "") }
    }

    func read(directory: URL) throws -> Reading {
        let sudo = try String(contentsOf: directory.appending(path: "sudo"), encoding: .utf8)
        let localURL = directory.appending(path: "sudo_local")
        let local = FileManager.default.fileExists(atPath: localURL.path)
            ? try String(contentsOf: localURL, encoding: .utf8) : nil
        return Reading(sudo: sudo, local: local)
    }
}
