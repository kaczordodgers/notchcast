import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ConvertFilesNative {
    @concurrent
    static func run(operation: String, format: String, inputs: [URL], output: URL) async throws {
        try Task.checkCancellation()
        func fail(_ message: String = String(localized: "The file cannot be converted with these options.")) throws -> Never {
            throw ConvertFilesPlan.Failure(message: message)
        }
        if operation.hasPrefix("pdf-") {
            let result = PDFDocument()
            var text = ""
            for input in inputs {
                try Task.checkCancellation()
                guard let document = PDFDocument(url: input), !document.isLocked else { try fail() }
                var indices = Array(0..<document.pageCount)
                if operation == "pdf-range" {
                    indices = []
                    for part in format.split(separator: ",") {
                        let bounds = part.trimmingCharacters(in: .whitespaces).split(separator: "-")
                        guard let first = bounds.first.flatMap({ Int($0) }), first > 0,
                              let last = bounds.last.flatMap({ Int($0) }), last >= first,
                              last <= document.pageCount else { try fail() }
                        indices += (first...last).map { $0 - 1 }
                    }
                    guard !indices.isEmpty else { try fail() }
                }
                if operation == "pdf-split" {
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
                }
                for index in indices {
                    try Task.checkCancellation()
                    guard let page = document.page(at: index) else { try fail() }
                    if operation == "pdf-text" {
                        text += (page.string ?? "") + "\n"
                    } else if operation == "pdf-split" {
                        let single = PDFDocument()
                        single.insert(page, at: 0)
                        guard single.write(to: output.appending(path: "page-\(index + 1).pdf")) else {
                            try fail()
                        }
                    } else { result.insert(page, at: result.pageCount) }
                }
            }
            try Task.checkCancellation()
            if operation == "pdf-text" {
                try text.write(to: output, atomically: false, encoding: .utf8)
            } else if operation != "pdf-split", !result.write(to: output) { try fail() }
        } else if operation == "image" {
            guard let source = CGImageSourceCreateWithURL(inputs[0] as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                try fail()
            }
            try Task.checkCancellation()
            if format == "pdf" {
                var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                guard let context = CGContext(output as CFURL, mediaBox: &box, nil) else { try fail() }
                context.beginPDFPage(nil)
                context.draw(image, in: box)
                context.endPDFPage()
                context.closePDF()
            } else {
                guard let type = UTType(filenameExtension: format),
                      let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil)
                else { try fail() }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { try fail() }
            }
        } else if operation == "data" {
            let input = inputs[0]
            let text = try String(contentsOf: input, encoding: .utf8)
            func scalar(_ text: String) throws -> Any {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if let data = trimmed.data(using: .utf8),
                   let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) { return value }
                guard !trimmed.contains("&"), !trimmed.contains("*"), !trimmed.hasPrefix("!"),
                      !trimmed.contains(": "), !trimmed.contains("#"),
                      !["|", ">"].contains(trimmed), !trimmed.hasPrefix("'") else {
                    try fail()
                }
                return trimmed
            }
            func quoted(_ value: Any) throws -> String {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
                guard let text = String(bytes: data, encoding: .utf8) else { try fail() }
                return text
            }
            let value: Any
            switch input.pathExtension.lowercased() {
            case "json": value = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
            case "yaml", "yml", "toml":
                var map: [String: Any] = [:]
                let separator: Character = input.pathExtension == "toml" ? "=" : ":"
                for line in text.split(whereSeparator: \.isNewline) {
                    try Task.checkCancellation()
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
                    guard line.first?.isWhitespace != true, let split = line.firstIndex(of: separator) else {
                        try fail(String(localized: "Only flat YAML and TOML tables are supported."))
                    }
                    let key = line[..<split].trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty, map[key] == nil else { try fail() }
                    let raw = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespaces)
                    guard key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
                          !raw.isEmpty, !raw.hasPrefix("["), !raw.hasPrefix("{") else {
                        try fail(String(localized: "Only flat YAML and TOML tables are supported."))
                    }
                    map[key] = try scalar(raw)
                }
                value = map
            case "csv":
                var rows: [[String]] = [], row: [String] = [], field = "", inside = false
                var iterator = text.makeIterator()
                var character = iterator.next()
                while let current = character {
                    try Task.checkCancellation()
                    if current == "\"" {
                        let next = iterator.next()
                        if inside && next == "\"" { field.append("\""); character = iterator.next(); continue }
                        inside.toggle()
                        character = next
                        continue
                    }
                    if !inside && (current == "," || current == "\n") {
                        row.append(field); field = ""
                        if current == "\n" { rows.append(row); row = [] }
                    } else if current != "\r" || inside { field.append(current) }
                    character = iterator.next()
                }
                guard !inside else { try fail() }
                if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
                guard let header = rows.first, Set(header).count == header.count else { try fail() }
                value = try rows.dropFirst().map { row -> [String: String] in
                    try Task.checkCancellation()
                    guard row.count == header.count else { try fail() }
                    return Dictionary(uniqueKeysWithValues: zip(header, row))
                }
            default: try fail()
            }
            let result: String
            switch format {
            case "json": result = try quoted(value) + "\n"
            case "yaml", "yml", "toml":
                guard let map = value as? [String: Any] else { try fail() }
                result = try map.keys.sorted().map { key in
                    try Task.checkCancellation()
                    guard key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
                          !(map[key]! is [Any]), !(map[key]! is [String: Any]) else {
                        try fail(String(localized: "Only flat YAML and TOML tables are supported."))
                    }
                    return key + (format == "toml" ? " = " : ": ") + (try quoted(map[key]!))
                }.joined(separator: "\n") + "\n"
            case "csv":
                guard let rows = value as? [[String: Any]], let first = rows.first else {
                    try fail()
                }
                let keys = first.keys.sorted()
                func csv(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                result = try ([keys.map(csv).joined(separator: ",")] + rows.map { row in
                    try Task.checkCancellation()
                    guard Set(row.keys) == Set(keys) else { try fail() }
                    return try keys.map { key in
                        let cell = row[key]!
                        guard !(cell is [Any]), !(cell is [String: Any]) else { try fail() }
                        let text = try (cell as? String) ?? quoted(cell)
                        return csv(text)
                    }.joined(separator: ",")
                }).joined(separator: "\n") + "\n"
            default: try fail()
            }
            try result.write(to: output, atomically: false, encoding: .utf8)
        } else { try fail() }
        try Task.checkCancellation()
    }
}
