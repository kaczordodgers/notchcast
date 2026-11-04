import Foundation

extension ArchiveFailure {
    var message: String {
        switch self {
        case .toolMissing: String(localized: "hatchzip is not installed.")
        case .unsupportedFormat: String(localized: "This archive format is not supported.")
        case .invalidListing: String(localized: "Couldn’t read the archive’s contents.")
        case .unsafePath(let path): String(localized: "The archive contains an unsafe path: \(path)")
        case .collision(let path): String(localized: "The archive contains conflicting paths: \(path)")
        case .symlinkAncestor(let path): String(localized: "The archive writes through a symbolic link: \(path)")
        case .tooManyEntries: String(localized: "The archive contains more than 100,000 entries.")
        case .expansionLimit: String(localized: "The archive exceeds the safe expansion limit.")
        case .insufficientSpace: String(localized: "Extraction would leave less than 2 GB free.")
        case .passwordRequired: String(localized: "This archive requires a password.")
        case .damagedArchive: String(localized: "The archive is damaged or incomplete.")
        case .existingProgress: String(localized: "Existing extraction progress needs in-place mode to resume.")
        case .toolFailed(let status): String(localized: "hatchzip stopped with code \(status).")
        case .filesystem: String(localized: "Couldn’t read or write the archive’s files.")
        }
    }
}
