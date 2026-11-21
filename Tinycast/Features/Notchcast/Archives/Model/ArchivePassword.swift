import Foundation

nonisolated enum ArchivePassword {
    static let variable = "HATCHZIP_PASSWORD"
    /// HatchZip's own count when it asks on a terminal.
    static let attempts = 3

    enum Step: Equatable, Sendable {
        case ask(wrong: Bool)
        case giveUp
    }

    static func next(asked: Int) -> Step { asked < attempts ? .ask(wrong: asked > 0) : .giveUp }

    static func environment(_ password: String?, engine: ArchiveEngine) -> [String: String] {
        guard engine == .hatchzip, let password else { return [:] }
        return [variable: password]
    }

    /// HatchZip cannot restore encrypted 7z or RAR names without a password.
    static func allowsInPlace(fileName: String) -> Bool { fileName.lowercased().hasSuffix(".zip") }
}
