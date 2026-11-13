// notchcast-sources: Tinycast/Features/Distill/Convert/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
import Foundation

@main
struct DistillSizeCapTest {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let source = root.appendingPathComponent("large.txt")
        precondition(FileManager.default.createFile(atPath: source.path, contents: nil))
        let file = try FileHandle(forWritingTo: source)
        try file.truncate(atOffset: UInt64(DistillFileAccess.maximumBytes))
        let identity = try DistillFileAccess.identity(source)
        precondition(identity.size == DistillFileAccess.maximumBytes)
        try file.truncate(atOffset: UInt64(DistillFileAccess.maximumBytes + 1))
        try file.close()
        do {
            _ = try DistillFileAccess.snapshot(source, in: root)
            preconditionFailure("Oversized source must be refused")
        } catch DistillConversion.Failure.tooLarge {
            print("PASS size cap accepts boundary and refuses one byte over with tooLarge")
        }
    }
}
