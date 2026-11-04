import Foundation

nonisolated enum MediaNetwork {
    static func expectedSize(_ output: String) -> Int64? {
        guard let line = output.split(whereSeparator: \.isNewline).last,
              let size = Int64(line), size > 0 else { return nil }
        return size
    }
}
