import CoreFoundation
import Foundation

nonisolated enum DistillMHTML {
    struct Body {
        let text: String
        let location: URL?
        let isHTML: Bool
    }

    private struct Part {
        let headers: [String: String]
        let payload: String

        var contentType: String { headers["content-type"] ?? "text/plain" }
    }

    static func body(_ data: Data) throws -> Body {
        guard let raw = String(bytes: data, encoding: .isoLatin1) else { throw DistillConversion.Failure.unreadable }
        let message = try part(raw)
        let leaves = try leaves(message, depth: 0)
        let candidates = leaves.filter {
            !$0.headers["content-disposition", default: ""].lowercased().hasPrefix("attachment")
                && ["text/html", "text/plain"].contains(mimeType($0.contentType))
        }
        let start = parameter("start", in: message.contentType)
        let selected = candidates.first { start != nil && $0.headers["content-id"] == start }
            ?? candidates.first { mimeType($0.contentType) == "text/html" } ?? candidates.first
        guard let selected else { throw DistillConversion.Failure.unreadable }
        let payload = try decoded(selected)
        let charset = parameter("charset", in: selected.contentType) ?? "utf-8"
        let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard encoding != kCFStringEncodingInvalidId else { throw DistillConversion.Failure.unreadable }
        let stringEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
        guard let text = String(bytes: payload, encoding: stringEncoding),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw DistillConversion.Failure.unreadable }
        let location = selected.headers["content-location"].flatMap(URL.init(string:))
        return Body(text: text, location: location, isHTML: mimeType(selected.contentType) == "text/html")
    }

    private static func part(_ raw: String) throws -> Part {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let split = normalized.range(of: "\n\n") else { throw DistillConversion.Failure.unreadable }
        var fields: [String] = []
        for line in normalized[..<split.lowerBound].components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !fields.isEmpty {
                fields[fields.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else { fields.append(line) }
        }
        var headers: [String: String] = [:]
        for field in fields {
            guard let colon = field.firstIndex(of: ":") else { throw DistillConversion.Failure.unreadable }
            let key = field[..<colon].lowercased()
            guard headers[key] == nil else { throw DistillConversion.Failure.unreadable }
            headers[key] = field[field.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return Part(headers: headers, payload: String(normalized[split.upperBound...]))
    }

    private static func leaves(_ part: Part, depth: Int) throws -> [Part] {
        guard depth < 16 else { throw DistillConversion.Failure.unreadable }
        guard mimeType(part.contentType).hasPrefix("multipart/") else { return [part] }
        guard let boundary = parameter("boundary", in: part.contentType), !boundary.isEmpty else {
            throw DistillConversion.Failure.unreadable
        }
        var segments: [String] = []
        var current: [String]?
        var closed = false
        for line in part.payload.components(separatedBy: "\n") {
            let marker = line.trimmingCharacters(in: .whitespaces)
            if marker == "--" + boundary || marker == "--" + boundary + "--" {
                if let current { segments.append(current.joined(separator: "\n")) }
                if marker == "--" + boundary + "--" { closed = true; break }
                current = []
            } else { current?.append(line) }
        }
        guard closed, !segments.isEmpty else { throw DistillConversion.Failure.unreadable }
        return try segments.flatMap { try leaves(Self.part($0), depth: depth + 1) }
    }

    private static func mimeType(_ value: String) -> String {
        value.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func parameter(_ name: String, in value: String) -> String? {
        let pattern = "(?:^|;)\\s*" + name + "\\s*=\\s*(?:\"([^\"]*)\"|([^;\\s]+))"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        for index in 1...2 {
            if let range = Range(match.range(at: index), in: value) { return String(value[range]) }
        }
        return nil
    }

    private static func decoded(_ part: Part) throws -> Data {
        switch part.headers["content-transfer-encoding", default: "8bit"].lowercased() {
        case "base64":
            let compact = String(part.payload.filter { !$0.isWhitespace })
            guard let decoded = Data(base64Encoded: compact) else { throw DistillConversion.Failure.unreadable }
            return decoded
        case "quoted-printable":
            guard let data = part.payload.data(using: .isoLatin1) else { throw DistillConversion.Failure.unreadable }
            let bytes = Array(data)
            var result = Data()
            var index = 0
            while index < bytes.count {
                guard bytes[index] == 61 else { result.append(bytes[index]); index += 1; continue }
                if index + 1 < bytes.count, bytes[index + 1] == 10 { index += 2; continue }
                guard index + 2 < bytes.count,
                    let digits = String(bytes: bytes[(index + 1)...(index + 2)], encoding: .ascii),
                    let byte = UInt8(digits, radix: 16)
                else { throw DistillConversion.Failure.unreadable }
                result.append(byte)
                index += 3
            }
            return result
        case "7bit", "8bit", "binary":
            guard let data = part.payload.data(using: .isoLatin1) else { throw DistillConversion.Failure.unreadable }
            return data
        default: throw DistillConversion.Failure.unreadable
        }
    }
}
