import Foundation

extension ArchiveFailure {
    var message: String {
        switch self {
        case .toolMissing: String(localized: "hatchzip is not installed.", table: "Notchcast")
        case .unsupportedFormat: String(localized: "This archive format is not supported.", table: "Notchcast")
        case .invalidListing: String(localized: "Couldn’t read the archive’s contents.", table: "Notchcast")
        case .unsafePath(let path): String(localized: "The archive contains an unsafe path: \(path)", table: "Notchcast")
        case .collision(let path): String(localized: "The archive contains conflicting paths: \(path)", table: "Notchcast")
        case .symlinkAncestor(let path): String(localized: "The archive writes through a symbolic link: \(path)", table: "Notchcast")
        case .tooManyEntries: String(localized: "The archive contains more than 100,000 entries.", table: "Notchcast")
        case .expansionLimit: String(localized: "The archive exceeds the safe expansion limit.", table: "Notchcast")
        case .insufficientSpace: String(localized: "Extraction would leave less than 2 GB free.", table: "Notchcast")
        case .passwordRequired: String(localized: "This archive requires a password.", table: "Notchcast")
        case .damagedArchive: String(localized: "The archive is damaged or incomplete.", table: "Notchcast")
        case .existingProgress: String(localized: "Existing extraction progress needs in-place mode to resume.", table: "Notchcast")
        case .toolFailed(let status): String(localized: "hatchzip stopped with code \(status).", table: "Notchcast")
        case .filesystem: String(localized: "Couldn’t read or write the archive’s files.", table: "Notchcast")
        }
    }
}
