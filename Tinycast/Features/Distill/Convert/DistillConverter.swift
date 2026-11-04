import Foundation

nonisolated struct DistillConverter: Sendable {
    typealias HTML = @Sendable (String, URL?) async throws -> DistillConversion
    typealias Media = @Sendable (URL) async throws -> DistillConversion
    typealias Trash = @Sendable (URL) throws -> Void

    var html: HTML?
    var media: Media?
    var trash: Trash = { source in try FileManager.default.trashItem(at: source, resultingItemURL: nil) }

    static var manifestName: String {
        ".distill-convert-\(Bundle.main.bundleIdentifier ?? "tests").json"
    }

    private struct Receipt: Codable {
        let sourceHash: String
        let outputName: String
        let outputHash: String
        let retainSource: Bool
    }

    @concurrent
    func convert(
        folder: URL, report: @Sendable (DistillConversion.Result) async -> Void = { _ in }
    ) async throws -> [DistillConversion.Result] {
        let input = folder.standardizedFileURL.resolvingSymlinksInPath()
        let isDirectory = try input.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let root = (isDirectory.isDirectory == true && isDirectory.isSymbolicLink != true
            ? input : input.deletingLastPathComponent()).resolvingSymlinksInPath()
        let manifest = root.appendingPathComponent(Self.manifestName)
        var receipts = try loadReceipts(manifest, root: root)
        let sources = isDirectory.isDirectory == true && isDirectory.isSymbolicLink != true
            ? try scan(root) : [input]
        var results: [DistillConversion.Result] = []
        for source in sources {
            try Task.checkCancellation()
            let result = try await convert(source, root: root, manifest: manifest, receipts: &receipts)
            results.append(result)
            await report(result)
        }
        return results
    }

    private func convert(
        _ source: URL, root: URL, manifest: URL, receipts: inout [String: Receipt]
    ) async throws -> DistillConversion.Result {
        var output: URL?
        do {
            if let reason = try skipReason(source) {
                return .init(source: source, output: nil, status: .skipped(reason))
            }
            let original = try DistillFileAccess.snapshot(source, in: root)
            let key = String(source.path.dropFirst(root.path.count + 1))
            let receipt: Receipt
            if let prior = receipts[key], let existing = try verifiedOutput(prior, source: source, root: root),
                prior.sourceHash == original.hash {
                output = existing
                receipt = prior
            } else {
                var document = try await read(source)
                try Task.checkCancellation()
                guard !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DistillConversion.Failure.empty
                }
                if document.retainSource {
                    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()%"))
                    guard let link = source.lastPathComponent.addingPercentEncoding(withAllowedCharacters: allowed) else {
                        throw DistillConversion.Failure.unsafePath
                    }
                    document.markdown += "\n[Original source](\(link))\n"
                }
                let data = Data(document.markdown.utf8)
                guard data.count <= DistillFileAccess.maximumBytes else { throw DistillConversion.Failure.tooLarge }
                guard try DistillFileAccess.snapshot(source, in: root) == original else {
                    throw DistillConversion.Failure.sourceChanged
                }
                let target = try DistillFileAccess.output(for: source, matching: DistillFileAccess.hash(data), in: root)
                try DistillFileAccess.check(target.deletingLastPathComponent(), in: root, allowingRoot: true)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try data.write(to: target, options: .withoutOverwriting)
                }
                output = target
                receipt = Receipt(
                    sourceHash: original.hash, outputName: target.lastPathComponent,
                    outputHash: DistillFileAccess.hash(data), retainSource: document.retainSource)
                guard try verifiedOutput(receipt, source: source, root: root) != nil else {
                    throw DistillConversion.Failure.outputChanged
                }
                receipts[key] = receipt
                try saveReceipts(receipts, to: manifest, root: root)
            }
            try Task.checkCancellation()
            if receipt.retainSource { return .init(source: source, output: output, status: .retained) }
            guard try DistillFileAccess.snapshot(source, in: root) == original else {
                throw DistillConversion.Failure.sourceChanged
            }
            guard try verifiedOutput(receipt, source: source, root: root) != nil else {
                throw DistillConversion.Failure.outputChanged
            }
            guard try DistillFileAccess.identity(source) == original.identity else {
                throw DistillConversion.Failure.sourceChanged
            }
            try Task.checkCancellation()
            try trash(source)
            return .init(source: source, output: output, status: .converted)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .init(source: source, output: output, status: .failed(error.localizedDescription))
        }
    }

    private func read(_ source: URL) async throws -> DistillConversion {
        switch DistillSourceKind(source) {
        case .pdf: return try await DistillDocumentReader.pdf(source)
        case .office: return try DistillDocumentReader.office(source)
        case .image:
            let text = try await DistillOCR.recognize(DistillOCR.image(at: source))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DistillConversion.Failure.empty
            }
            var document = DistillConversion.literal(text, source: source, retainSource: true)
            document.markdown = "> Automatic OCR transcription; compare unclear wording with the original image.\n\n"
                + document.markdown
            return document
        case .text, .visualText:
            let text = try DistillFileAccess.text(source)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DistillConversion.Failure.empty
            }
            return .literal(text, source: source, retainSource: DistillSourceKind(source) == .visualText)
        case .html:
            let text = try DistillFileAccess.text(source)
            if try isHTMLCode(source) { return .literal(text, source: source) }
            guard let html else { throw DistillConversion.Failure.unreadable }
            return try await html(text, nil)
        case .mhtml:
            let body = try DistillMHTML.body(Data(contentsOf: source))
            if !body.isHTML { return .literal(body.text, source: source, retainSource: true) }
            guard let html else { throw DistillConversion.Failure.unreadable }
            var document = try await html(body.text, body.location)
            document.retainSource = true
            return document
        case .media:
            guard let media else { throw DistillConversion.Failure.unreadable }
            return try await media(source)
        case .unsupported: throw DistillConversion.Failure.unreadable
        }
    }

    private func isHTMLCode(_ source: URL) throws -> Bool {
        let parent = source.deletingLastPathComponent()
        if ["package.json", "tsconfig.json"].contains(where: {
            FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path)
        }) { return true }
        let manifest = parent.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return false }
        let data = try Data(contentsOf: manifest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return [2, 3].contains(json["manifest_version"] as? Int ?? 0)
    }

    private func skipReason(_ source: URL) throws -> DistillConversion.SkipReason? {
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true { return .symbolicLink }
        if DistillSourceKind.generatedFiles.contains(source.lastPathComponent) { return .generated }
        if source.pathExtension.lowercased() == "md" { return .markdown }
        switch DistillSourceKind(source) {
        case .unsupported: return .unsupported
        case .html where html == nil: return .htmlUnavailable
        case .mhtml where html == nil: return .htmlUnavailable
        case .media where media == nil: return .mediaUnavailable
        default: return nil
        }
    }

    private func scan(_ root: URL) throws -> [URL] {
        var scanError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in scanError = error; return false }
        ) else { throw DistillConversion.Failure.unreadable }
        var sources: [URL] = []
        for case let enumerated as URL in enumerator {
            let source = enumerated.standardizedFileURL
            let values = try source.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey
            ])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                sources.append(source)
            } else if values.isDirectory == true {
                if DistillSourceKind.skippedFolders.contains(source.lastPathComponent) {
                    enumerator.skipDescendants()
                } else if values.isPackage == true { sources.append(source) }
            } else if values.isRegularFile == true { sources.append(source) }
        }
        if let scanError { throw scanError }
        return sources.sorted {
            let left = DistillSourceKind($0).priority
            let right = DistillSourceKind($1).priority
            return left == right ? $0.path < $1.path : left < right
        }
    }

    private func verifiedOutput(_ receipt: Receipt, source: URL, root: URL) throws -> URL? {
        guard !receipt.outputName.isEmpty, !receipt.outputName.contains("/"),
            receipt.outputName.hasSuffix(".md") else { return nil }
        let output = source.deletingLastPathComponent().appendingPathComponent(receipt.outputName)
        guard output != source, FileManager.default.fileExists(atPath: output.path) else { return nil }
        let snapshot = try DistillFileAccess.snapshot(output, in: root)
        return snapshot.identity.size > 0 && snapshot.hash == receipt.outputHash ? output : nil
    }

    private func loadReceipts(_ manifest: URL, root: URL) throws -> [String: Receipt] {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [:] }
        try DistillFileAccess.check(manifest, in: root)
        _ = try DistillFileAccess.identity(manifest)
        return try JSONDecoder().decode([String: Receipt].self, from: Data(contentsOf: manifest))
    }

    private func saveReceipts(_ receipts: [String: Receipt], to manifest: URL, root: URL) throws {
        if FileManager.default.fileExists(atPath: manifest.path) { try DistillFileAccess.check(manifest, in: root) }
        try JSONEncoder().encode(receipts).write(to: manifest, options: .atomic)
    }
}
