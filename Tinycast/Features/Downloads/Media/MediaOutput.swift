import Foundation

nonisolated enum MediaOutput {
    struct Progress: Equatable, Sendable {
        var received: Int64?
        var total: Int64?
        var bytesPerSecond: Double?
        var eta: Double?
        var fraction: Double? {
            guard let received, let total, total > 0 else { return nil }
            return min(1, max(0, Double(received) / Double(total)))
        }
    }

    static func progress(_ line: String) -> Progress? {
        let prefix = "MEDIA_PROGRESS "
        guard line.hasPrefix(prefix) else { return nil }
        let fields = line.dropFirst(prefix.count).split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5 else { return nil }
        func number(_ value: String) -> Double? {
            guard let number = Double(value), number.isFinite, number >= 0 else { return nil }
            return number
        }
        func bytes(_ value: String) -> Int64? {
            guard let number = number(value), number < Double(Int64.max) else { return nil }
            return Int64(number)
        }
        return Progress(received: bytes(fields[0]), total: bytes(fields[1]) ?? bytes(fields[2]),
                        bytesPerSecond: number(fields[3]), eta: number(fields[4]))
    }

    static func outputPath(_ line: String, destination: URL) -> URL? {
        let prefix = "MEDIA_FILE "
        guard line.hasPrefix(prefix),
              let data = String(line.dropFirst(prefix.count)).data(using: .utf8),
              let path = try? JSONDecoder().decode(String.self, from: data), path.hasPrefix("/") else { return nil }
        let url = URL(filePath: path).standardizedFileURL
        let root = destination.standardizedFileURL.path
        guard url.path.hasPrefix(root == "/" ? root : root + "/") else { return nil }
        return url
    }
}
