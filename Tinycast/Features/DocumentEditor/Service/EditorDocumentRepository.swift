import Foundation

struct EditorDocumentRepository: Sendable {
    static func kind(of url: URL) throws -> Bool {
        guard url.isFileURL else { throw EditorFailure.unsupportedFile }
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return true
        case "txt", "text": return false
        default: throw EditorFailure.unsupportedFile
        }
    }

    @concurrent
    static func load(_ url: URL) async throws -> EditorDocumentSnapshot {
        try Task.checkCancellation()
        return try coordinated(url, writing: false) { location in
            try EditorDocumentSnapshot(bytes: read(location))
        }
    }

    @concurrent
    static func save(
        _ source: String, to url: URL, expecting snapshot: EditorDocumentSnapshot
    ) async throws -> EditorDocumentSnapshot {
        let bytes = try snapshot.encoded(source)
        return try coordinated(url, writing: true) { location in
            try Task.checkCancellation()
            guard try read(location) == snapshot.bytes else { throw EditorFailure.externalChange }
            if bytes != snapshot.bytes {
                let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
                if (attributes[.referenceCount] as? NSNumber)?.intValue ?? 1 > 1 {
                    let file = try FileHandle(forWritingTo: location)
                    defer { try? file.close() }
                    try file.truncate(atOffset: 0)
                    try file.write(contentsOf: bytes)
                    return try EditorDocumentSnapshot(bytes: bytes)
                }
                let temporary = location.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try bytes.write(to: temporary)
                _ = try FileManager.default.replaceItemAt(location, withItemAt: temporary)
            }
            return try EditorDocumentSnapshot(bytes: bytes)
        }
    }

    @concurrent
    static func create(_ source: String, at url: URL, format: EditorDocumentSnapshot) async throws -> EditorDocumentSnapshot {
        let bytes = try format.encoded(source)
        return try coordinated(url, writing: true) { location in
            try Task.checkCancellation()
            let temporary = location.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
            do {
                try bytes.write(to: temporary, options: .atomic)
                try FileManager.default.moveItem(at: temporary, to: location)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
            return try EditorDocumentSnapshot(bytes: bytes)
        }
    }

    private static func read(_ url: URL) throws -> Data {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw EditorFailure.unsupportedFile
            }
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw EditorFailure.missingFile
        }
    }

    private static func coordinated<Value>(
        _ url: URL, writing: Bool, operation: (URL) throws -> Value
    ) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        var result: Result<Value, Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { location in
                result = Result { try operation(location) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error) { location in
                result = Result { try operation(location) }
            }
        }
        if let result { return try result.get() }
        if let error {
            if error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileReadNoSuchFile.rawValue {
                throw EditorFailure.missingFile
            }
            throw error
        }
        throw CocoaError(.fileReadUnknown)
    }
}
