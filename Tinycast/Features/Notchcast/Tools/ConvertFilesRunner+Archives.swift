import Foundation

extension ConvertFilesRunner {
    /// Hub glue, so neither the Convert Files nor the Archives folder names the other.
    static func archive(_ operation: String, _ sources: [URL]) async throws -> URL {
        do {
            if operation == "extract" { return try await ArchiveExtractionRunner().extract(sources[0]) }
            guard let format = ArchiveCompression.allCases.first(where: { $0.suffix == operation }) else {
                throw ConvertFilesPlan.Failure(message: String(
                    localized: "This file conversion is not supported.", table: "Notchcast"))
            }
            return try await ArchiveCompressor().compress(sources, format: format)
        } catch let failure as ArchiveFailure {
            throw ConvertFilesPlan.Failure(message: failure.message)
        }
    }
}
