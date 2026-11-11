// notchcast-sources: Tinycast/Features/ConvertFiles/Model/*.swift
// notchcast-sources: Tinycast/Features/ConvertFiles/Service/ConvertFilesRunner.swift
// notchcast-sources: Tinycast/Features/ConvertFiles/Service/ConvertFilesNative.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/*.swift Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Tools/ConvertFilesRunner+Archives.swift
// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Platform/AppPaths.swift
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
            "-nostore", "-strip", "-output", ConvertFilesPlan.outputPlaceholder, source.path])
        precondition(plan.items[0].stem == "a 'quoted' file" && plan.items[0].suffix == ".rtf")
        for (input, target, tool) in [("png", "jpg", "native"), ("png", "webp", "cwebp"),
            ("png", "heic", "sips"), ("md", "html", "pandoc"), ("wav", "mp3", "ffmpeg"),
            ("mov", "mp4", "ffmpeg"), ("srt", "vtt", "ffmpeg"), ("json", "yaml", "native"),
            ("pdf", "pdf-split", "native"), ("zip", "extract", "archives"), ("txt", "zip", "archives"),
            ("txt", "7z", "archives"), ("txt", "tar.gz", "tar")] {
            let planned = try ConvertFilesPlan.make(sources: [url("input." + input)], target: target)
            precondition(planned.items[0].tool == tool)
        }
        do {
            _ = try ConvertFilesPlan.make(sources: [source], target: "mp4")
            preconditionFailure("Unsupported pair accepted")
        } catch is ConvertFilesPlan.Failure {}
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        func options(_ sources: [String], _ target: String) throws -> Data {
            try DownloadJob.encode(ConvertFilesRunner.Options(sources: sources, target: target))
        }
        let job = DownloadJob(id: "test", kind: "convert-files", source: source.path, title: "test",
                              created: Date(), encodedOptions: try options([source.path], "rtf"))
        let fake = ConvertFilesRunner(process: { _, arguments, _ in
            let output = arguments[arguments.firstIndex(of: "-output")! + 1]
            try Data("converted".utf8).write(to: URL(fileURLWithPath: output))
        })
        let context = DownloadRunContext(destination: temporary, tools: DownloadToolLookup())
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
        var legacy = job
        legacy.encodedOptions = nil
        do {
            _ = try await fake.run(legacy, context: context)
            preconditionFailure("A job without options ran")
        } catch let failure as ConvertFilesPlan.Failure {
            precondition(failure.message.contains("Add the files again"), "an older build's job says what to do")
        }
        let other = url("failed.txt")
        try "failure".write(to: other, atomically: true, encoding: .utf8)
        var batch = job
        batch.encodedOptions = try options([source.path, other.path], "rtf")
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
        let raced = url("race.txt")
        try "race".write(to: raced, atomically: true, encoding: .utf8)
        try "taken".write(to: url("race.rtf"), atomically: true, encoding: .utf8)
        let racing = ConvertFilesRunner(process: { _, arguments, _ in
            // Taken after planning, before publish: the name is chosen once, at publish.
            try Data("late".utf8).write(to: temporary.appending(path: "race (2).rtf"))
            let output = arguments[arguments.firstIndex(of: "-output")! + 1]
            try Data("converted".utf8).write(to: URL(fileURLWithPath: output))
        })
        var raceJob = job
        raceJob.encodedOptions = try options([raced.path], "rtf")
        let racedOutput = try await racing.run(raceJob, context: context)
        precondition(racedOutput?.lastPathComponent == "race (3).rtf", "publish numbers once, not twice")
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
        imageJob.encodedOptions = try options([imageURL.path], "jpg")
        guard let nativeImage = try await native.run(imageJob, context: nativeContext) else {
            preconditionFailure("No native image output")
        }
        precondition(CGImageSourceCreateWithURL(nativeImage as CFURL, nil) != nil)
        for operation in ["pdf-merge", "pdf-split"] {
            let inputs = operation == "pdf-merge" ? [url("input.pdf").path, url("input.pdf").path] : [url("input.pdf").path]
            var nativeJob = job
            nativeJob.source = inputs[0]
            nativeJob.encodedOptions = try options(inputs, operation)
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
            nativeJob.encodedOptions = try options([input.path], target)
            guard let output = try await native.run(nativeJob, context: nativeContext) else {
                preconditionFailure("No native data output")
            }
            let converted = try String(contentsOf: output, encoding: .utf8)
            precondition(converted.contains("hello"))
            try manager.removeItem(at: output)
        }
        var zipJob = job
        zipJob.encodedOptions = try options([source.path], "zip")
        let zipped = try await native.run(zipJob, context: nativeContext)
        precondition(zipped?.lastPathComponent == "a 'quoted' file.txt.zip", "Archives builds and names the zip")
        let savedParents = UserDefaults.standard.stringArray(forKey: "archiveRecoveryParents")
        defer { UserDefaults.standard.set(savedParents, forKey: "archiveRecoveryParents") }
        let bundle = url("bundle")
        try manager.createDirectory(at: bundle, withIntermediateDirectories: false)
        for name in ["one.txt", "two.txt"] { try Data(name.utf8).write(to: bundle.appending(path: name)) }
        let packed = url("bundle.tar.bz2")
        let packing = try await ArchiveProcess.run(tool: URL(filePath: "/usr/bin/tar"),
            arguments: ["-cjf", packed.path, "-C", bundle.path, "one.txt", "two.txt"])
        precondition(packing.status == 0)
        try manager.removeItem(at: bundle)
        let warning = Data("0081;00000000;Safari;".utf8)
        let marked = warning.withUnsafeBytes {
            setxattr(packed.path, "com.apple.quarantine", $0.baseAddress, warning.count, 0, 0)
        }
        precondition(marked == 0)
        var extractJob = job
        extractJob.encodedOptions = try options([packed.path], "extract")
        guard let unpacked = try await ConvertFilesRunner().run(extractJob, context: context) else {
            preconditionFailure("No extraction output")
        }
        let carried = try ArchiveFiles.quarantine(unpacked.appending(path: "one.txt"))
        precondition(carried == warning, "extracted files keep the archive's quarantine")
        precondition(unpacked.lastPathComponent == "bundle", "Archives names the extracted folder")
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
        textJob.encodedOptions = try options([textPDF.path], "txt")
        let textOutput = try await native.run(textJob, context: nativeContext)!
        let extracted = try String(contentsOf: textOutput, encoding: .utf8)
        precondition(extracted.contains("Generated text"))
        for (ext, content) in [("yaml", "parent:\n  child: 1"), ("toml", "parent.child = 1"),
                               ("toml", "parent = {child = 1}")] {
            let input = url("nested." + ext)
            try content.write(to: input, atomically: true, encoding: .utf8)
            var nested = job
            nested.source = input.path
            nested.encodedOptions = try options([input.path], "json")
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
