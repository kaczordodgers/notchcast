import Foundation

nonisolated struct TweakProfileRunner: Sendable {
    let open: @Sendable (URL) throws -> Void

    @concurrent
    func requestApproval(data: Data, folder: URL) async throws -> URL {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(UUID().uuidString + ".mobileconfig")
        try data.write(to: file, options: .atomic)
        do {
            try Task.checkCancellation()
            try open(file)
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}
