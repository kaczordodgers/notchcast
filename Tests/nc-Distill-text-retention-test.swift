// notchcast-sources: Tinycast/Features/Distill/Convert/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
import Foundation

@main
struct DistillTextRetentionTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Channel - Title.txt")
        let data = Data("TRANSCRIPT 1234".utf8)
        try data.write(to: source)
        let converter = DistillConverter(trash: { _ in preconditionFailure("Text must never reach Trash") })
        let first = try await converter.convert(folder: root)
        precondition(first.first?.status == .retained)
        precondition(try Data(contentsOf: source) == data)
        let manifest = root.appendingPathComponent(DistillConverter.manifestName)
        var receipts = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: [String: Any]]
        receipts[source.lastPathComponent]!["retainSource"] = false
        try JSONSerialization.data(withJSONObject: receipts).write(to: manifest)
        let repeated = try await converter.convert(folder: root)
        precondition(repeated.first { $0.source == source }?.status == .retained)
        precondition(try Data(contentsOf: source) == data)
        print("PASS text retained on fresh conversion and legacy receipt reuse")
    }
}
