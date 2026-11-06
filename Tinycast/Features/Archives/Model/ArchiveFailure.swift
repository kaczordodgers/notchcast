import Foundation

nonisolated enum ArchiveFailure: Error, Equatable, Sendable {
    case compressionToolMissing(String)
    case compressionFailed(Int32)
    case toolMissing
    case unsupportedFormat
    case invalidListing
    case unsafePath(String)
    case collision(String)
    case symlinkAncestor(String)
    case tooManyEntries
    case expansionLimit
    case insufficientSpace
    case passwordRequired
    case damagedArchive
    case existingProgress
    case toolFailed(Int32)
    case filesystem(String)
}
