import Foundation

extension ConvertFilesRunner {
    /// Hub glue: Convert Files packs and unpacks through Archives, so neither feature folder names the other.
    static func archive(_ operation: String, _ sources: [URL]) async throws -> URL {
        do {
            guard let format = ArchiveCompression.allCases.first(where: { $0.suffix == operation }) else {
                return try await ArchiveExtractionRunner().extract(sources[0])
            }
            return try await ArchiveCompressor().compress(sources, format: format)
        } catch let failure as ArchiveFailure {
            throw ConvertFilesPlan.Failure(message: failure.message)
        }
    }
}
