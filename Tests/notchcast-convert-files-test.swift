// notchcast-sources: Tinycast/Features/ConvertFiles/Model/*.swift
// notchcast-sources: Tinycast/Features/ConvertFiles/Service/ConvertFilesRunner.swift
// notchcast-sources: Tinycast/Features/ConvertFiles/Service/ConvertFilesNative.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/NotificationToken.swift
import Foundation
import PDFKit

@main
struct ConvertFilesTests {
    static func main() async throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appending(path: UUID().uuidString)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: temporary) }
        func url(_ name: String) -> URL { temporary.appending(path: name) }
        let source = url("a 'quoted' file.txt")
        let plan = try ConvertFilesPlan.make(sources: [source], target: "rtf")
        precondition(plan.items[0].arguments == ["-convert", "rtf", "-encoding", "UTF-8", "-noload",
            "-nostore", "-strip", "-output", url("a 'quoted' file.rtf").path, source.path])
        let collision = try ConvertFilesPlan.make(sources: [source], target: "rtf", occupied: [plan.items[0].output])
        precondition(collision.items[0].output.lastPathComponent == "a 'quoted' file (2).rtf")
        for (input, target, tool) in [("png", "jpg", "swift"), ("png", "webp", "cwebp"),
            ("png", "heic", "sips"), ("md", "html", "pandoc"), ("wav", "mp3", "ffmpeg"),
            ("mov", "mp4", "ffmpeg"), ("srt", "vtt", "ffmpeg"), ("json", "yaml", "swift"),
            ("pdf", "pdf-split", "swift"), ("zip", "extract", "tar"), ("txt", "zip", "tar")] {
            let planned = try ConvertFilesPlan.make(sources: [url("input." + input)], target: target)
            precondition(planned.items[0].tool == tool)
        }
        do {
            _ = try ConvertFilesPlan.make(sources: [source], target: "mp4")
            preconditionFailure("Unsupported pair accepted")
        } catch is ConvertFilesPlan.Failure {}
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let job = DownloadJob(id: "test", kind: "convert-files", source: source.path, title: "test",
                              created: Date(), options: ["target": "rtf"])
        let fake = ConvertFilesRunner(process: { _, arguments, _ in
            let output = arguments[arguments.firstIndex(of: "-output")! + 1]
            try Data("converted".utf8).write(to: URL(fileURLWithPath: output))
        })
        let context = DownloadRunContext(destination: temporary)
        let result = try await fake.run(job, context: context)
        precondition(result != nil)
        do {
            _ = try await fake.run(job, context: DownloadRunContext(destination: temporary,
                tools: DownloadToolLookup(directories: [])))
            preconditionFailure("Missing tool accepted")
        } catch { precondition(error.localizedDescription.contains("textutil")) }
        let cancelled = ConvertFilesRunner(process: { _, _, _ in throw CancellationError() })
        do {
            _ = try await cancelled.run(job, context: context)
            preconditionFailure("Cancellation swallowed")
        } catch is CancellationError {}
        let other = url("failed.txt")
        try "failure".write(to: other, atomically: true, encoding: .utf8)
        var batch = job
        let encoded = try JSONEncoder().encode([source.path, other.path])
        batch.options["sources"] = String(bytes: encoded, encoding: .utf8)
        let partial = ConvertFilesRunner(process: { _, arguments, _ in
            if arguments.last == other.path { throw ConvertFilesPlan.Failure(message: "Synthetic failure") }
            let output = arguments[arguments.firstIndex(of: "-output")! + 1]
            try Data("converted".utf8).write(to: URL(fileURLWithPath: output))
        })
        do {
            _ = try await partial.run(batch, context: context)
            preconditionFailure("Partial failure hidden")
        } catch { precondition(error.localizedDescription.contains("Synthetic failure")) }
        precondition(manager.fileExists(atPath: url("a 'quoted' file (2).rtf").path))
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        document.insert(PDFPage(), at: 1)
        precondition(document.write(to: url("input.pdf")))
        let helper = url("helper.swift")
        try ConvertFilesNative.source.write(to: helper, atomically: true, encoding: .utf8)
        for operation in ["pdf-merge", "pdf-split"] {
            let output = url(operation)
            let inputs = operation == "pdf-merge" ? [url("input.pdf").path, url("input.pdf").path] : [url("input.pdf").path]
            _ = try await context.spawn(executable: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: [helper.path, operation, ""] + inputs + [output.path])
            if operation == "pdf-merge" {
                precondition(PDFDocument(url: output)?.pageCount == 4)
            } else {
                let files = try manager.contentsOfDirectory(atPath: output.path)
                precondition(files.count == 2)
            }
        }
        for (ext, text, target) in [("json", "{\"name\":\"hello\",\"count\":2}", "toml"),
            ("yaml", "name: \"hello\"\ncount: 2\n", "json"),
            ("toml", "name = \"hello\"\ncount = 2\n", "yaml"),
            ("csv", "name,count\n\"hello, world\",2\n", "json"),
            ("json", "[{\"name\":\"hello, world\",\"count\":2}]", "csv")] {
            let input = url("fixture." + ext)
            try text.write(to: input, atomically: true, encoding: .utf8)
            let output = url("fixture-output." + target)
            _ = try await context.spawn(executable: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: [helper.path, "data", target, input.path, output.path])
            let converted = try String(contentsOf: output, encoding: .utf8)
            precondition(converted.contains("hello"))
            try manager.removeItem(at: output)
        }
        print("Convert Files tests passed")
    }
}
