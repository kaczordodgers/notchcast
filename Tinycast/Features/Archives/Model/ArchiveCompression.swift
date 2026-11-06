import Foundation

nonisolated enum ArchiveCompression: String, Equatable, Sendable, CaseIterable {
    case zip, small, fast

    var suffix: String {
        switch self {
        case .zip: "zip"
        case .small: "7z"
        case .fast: "tar.zst"
        }
    }

    func arguments(sources: [URL], output: URL, zstd: URL? = nil) -> [String] {
        switch self {
        case .zip: ["-c", "-k", "--sequesterRsrc", "--keepParent"] + sources.map(\.path) + [output.path]
        case .small: ["a", "-t7z", "-mx=9", output.path, "--"] + sources.map(\.path)
        case .fast: ["--use-compress-program", "\"\(zstd!.path)\" -T0", "-cf", output.path]
            + sources.flatMap { ["-C", $0.deletingLastPathComponent().path, "./" + $0.lastPathComponent] }
        }
    }

    func output(sources: [URL], exists: (URL) -> Bool) -> URL {
        let parent = sources[0].deletingLastPathComponent()
        let common = sources.allSatisfy { $0.deletingLastPathComponent() == parent }
        let name = sources.count == 1 ? sources[0].lastPathComponent
            : common && !parent.lastPathComponent.isEmpty ? parent.lastPathComponent : "Archive"
        var number = 1
        var candidate = parent.appending(path: "\(name).\(suffix)")
        while exists(candidate) {
            number += 1
            candidate = parent.appending(path: "\(name) \(number).\(suffix)")
        }
        return candidate
    }
}
