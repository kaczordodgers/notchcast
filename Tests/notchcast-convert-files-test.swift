// notchcast-sources: Tinycast/Features/ConvertFiles/Model/*.swift
// notchcast-sources: Tinycast/Features/ConvertFiles/Service/ConvertFilesRunner.swift
// notchcast-sources: Tinycast/Features/ConvertFiles/Service/ConvertFilesNative.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/NotificationToken.swift
import Foundation
import PDFKit
import ImageIO
import CoreText

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
        for (input, target, tool) in [("png", "jpg", "native"), ("png", "webp", "cwebp"),
            ("png", "heic", "sips"), ("md", "html", "pandoc"), ("wav", "mp3", "ffmpeg"),
            ("mov", "mp4", "ffmpeg"), ("srt", "vtt", "ffmpeg"), ("json", "yaml", "native"),
            ("pdf", "pdf-split", "native"), ("zip", "extract", "tar"), ("txt", "zip", "tar")] {
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
        let native = ConvertFilesRunner(process: { _, _, _ in
            preconditionFailure("Native conversion launched a child process")
        })
        let nativeContext = DownloadRunContext(destination: temporary, tools: DownloadToolLookup(directories: []))
        let imageURL = url("native.png")
        let pixels = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = pixels.makeImage()!
        let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        var imageJob = job
        imageJob.source = imageURL.path
        imageJob.options = ["target": "jpg"]
        guard let nativeImage = try await native.run(imageJob, context: nativeContext) else {
            preconditionFailure("No native image output")
        }
        precondition(CGImageSourceCreateWithURL(nativeImage as CFURL, nil) != nil)
        for operation in ["pdf-merge", "pdf-split"] {
            let inputs = operation == "pdf-merge" ? [url("input.pdf").path, url("input.pdf").path] : [url("input.pdf").path]
            var nativeJob = job
            nativeJob.source = inputs[0]
            nativeJob.options = ["target": operation,
                "sources": String(bytes: try JSONEncoder().encode(inputs), encoding: .utf8)!]
            guard let output = try await native.run(nativeJob, context: nativeContext) else {
                preconditionFailure("No native PDF output")
            }
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
            var nativeJob = job
            nativeJob.source = input.path
            nativeJob.options = ["target": target]
            guard let output = try await native.run(nativeJob, context: nativeContext) else {
                preconditionFailure("No native data output")
            }
            let converted = try String(contentsOf: output, encoding: .utf8)
            precondition(converted.contains("hello"))
            try manager.removeItem(at: output)
        }
        let textPDF = url("text.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let pdf = CGContext(textPDF as CFURL, mediaBox: &box, nil)!
        pdf.beginPDFPage(nil)
        pdf.textPosition = CGPoint(x: 20, y: 100)
        let text = NSAttributedString(string: "Generated text", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        ])
        CTLineDraw(CTLineCreateWithAttributedString(text), pdf)
        pdf.endPDFPage()
        pdf.closePDF()
        var textJob = job
        textJob.source = textPDF.path
        textJob.options = ["target": "txt"]
        let textOutput = try await native.run(textJob, context: nativeContext)!
        let extracted = try String(contentsOf: textOutput, encoding: .utf8)
        precondition(extracted.contains("Generated text"))
        for (ext, content) in [("yaml", "parent:\n  child: 1"), ("toml", "parent.child = 1"),
                               ("toml", "parent = {child = 1}")] {
            let input = url("nested." + ext)
            try content.write(to: input, atomically: true, encoding: .utf8)
            var nested = job
            nested.source = input.path
            nested.options = ["target": "json"]
            do {
                _ = try await native.run(nested, context: nativeContext)
                preconditionFailure("Nested data accepted")
            } catch { precondition(error.localizedDescription.contains("flat")) }
        }
        let cancelledOutput = url("cancelled.pdf")
        let nativeTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await ConvertFilesNative.run(operation: "pdf-merge", format: "", inputs: [textPDF], output: cancelledOutput)
        }
        do {
            try await nativeTask.value
            preconditionFailure("Native cancellation swallowed")
        } catch is CancellationError {}
        precondition(!manager.fileExists(atPath: cancelledOutput.path))
        print("Convert Files tests passed")
    }
}
