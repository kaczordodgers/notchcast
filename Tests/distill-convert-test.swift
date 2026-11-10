// notchcast-sources: Tinycast/Features/Distill/Convert/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit

@main
@MainActor
struct DistillConvertTests {
    static var passes = 0
    static var failures = 0

    enum FixtureFailure: Error { case invalid, trashDenied }

    static func main() async {
        do { try await run() } catch {
            failures += 1
            print("FAIL: unexpected fixture error: \(error)")
        }
        print("distill-convert-test: \(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func run() async throws {
        let base = ProcessInfo.processInfo.environment["DISTILL_CONVERT_TEST_ROOT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory
        let root = base.appendingPathComponent("distill-convert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await nativeFormats(root)
        try await namingAndSkips(root)
        try await integrations(root)
        try await failureSafety(root)
        try await reviewRegressions(root)
        try await cancellation(root)
        try await realTrash(root)
        try await queueRunner(root)
    }

    static func queueRunner(_ root: URL) async throws {
        let folder = try directory("runner", in: root)
        let trash = try directory("runner-trash", in: root)
        let source = folder.appendingPathComponent("single.txt")
        try write("QUEUE SOURCE", "single.txt", in: folder)
        try write("KEEP SIBLING", "sibling.txt", in: folder)
        var progress: [DownloadProgress] = []
        let context = DownloadRunContext(destination: root, report: { progress.append($0) })
        let runner = DistillConvertRunner(trash: moveTo(trash))
        let job = DownloadJob(id: UUID().uuidString, kind: "convert", source: source.path,
                              title: "Fixture", created: Date())
        let output = try await runner.run(job, context: context)
        expect(try contents(output).contains("QUEUE SOURCE"), "queue runner returns single-file output")
        expect(exists(folder.appendingPathComponent("sibling.txt")), "single-file job leaves sibling untouched")
        expect(progress.count == 1, "queue runner reports through context")
        try write("<p>PAGE</p>", "page.html", in: folder)
        var batch = job
        batch.source = folder.path
        _ = try await runner.run(batch, context: context)
        expect(progress.contains { $0.stage?.contains("HTML converter is unavailable") == true },
               "queue progress explains missing HTML integration")
        try write("BROKEN PDF", "broken.pdf", in: folder)
        do {
            _ = try await runner.run(batch, context: context)
            expect(false, "queue runner fails a batch containing conversion failures")
        } catch { expect(true, "queue runner fails a batch containing conversion failures") }
    }

    static func nativeFormats(_ root: URL) async throws {
        let folder = try directory("native", in: root)
        let trash = try directory("native-trash", in: root)
        let image = try imageFixture()
        let png = folder.appendingPathComponent("scan.png")
        guard let destination = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil) else {
            throw FixtureFailure.invalid
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureFailure.invalid }
        let pdf = folder.appendingPathComponent("document.pdf")
        try pdfFixture(pdf, scan: image)
        let text = NSAttributedString(string: "OFFICE PARAGRAPH 6284\nSecond paragraph with café and 日本語.")
        for (suffix, type) in [
            ("rtf", NSAttributedString.DocumentType.rtf), ("docx", .officeOpenXML), ("doc", .docFormat), ("odt", .openDocument)
        ] {
            let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
            try data.write(to: folder.appendingPathComponent("office." + suffix))
        }
        try write("VERBATIM 1739\r\ntrailing spaces  \n```nested```\n~~~~\n", "plain.txt", in: folder)
        try write("{\"complete\": [1, 2, 3]}\n", "source.json", in: folder)
        let converter = DistillConverter(trash: moveTo(trash))
        let results = try await converter.convert(folder: folder)
        for result in results {
            if case .failed(let detail) = result.status {
                expect(false, "\(result.source.lastPathComponent): \(detail)")
            }
        }
        expect(results.count == 8, "all eight native source fixtures reported")
        let pdfText = try contents(output("document.pdf", in: results))
        expect(pdfText.contains("SELECTABLE DOCUMENT 4826"), "PDFKit extracts selectable text")
        expect(pdfText.contains("7391"), "Vision extracts scanned PDF page")
        expect(pdfText.contains("## Page 1") && pdfText.contains("## Page 2"), "all PDF pages are represented")
        expect(status("document.pdf", in: results) == .retained && exists(pdf), "PDF visual original is retained")
        expect(try contents(output("scan.png", in: results)).contains("7391"), "Vision recognizes rendered PNG text")
        expect(status("scan.png", in: results) == .retained && exists(png), "OCR original is retained")
        for suffix in ["rtf", "docx", "doc", "odt"] {
            let name = "office." + suffix
            expect(try contents(output(name, in: results)).contains("OFFICE PARAGRAPH 6284"), "native \(suffix) reader")
            expect(status(name, in: results) == .retained && exists(folder.appendingPathComponent(name)),
                   "\(suffix) fidelity retention")
        }
        let plain = try contents(output("plain.txt", in: results))
        expect(plain.contains("trailing spaces  \n```nested```"),
               "plain text preserves literal bytes and nested fences")
        expect(plain.contains("````\n"), "fence expands beyond source backticks")
        expect(status("plain.txt", in: results) == .converted, "verified text is moved to Trash")
        expect(!exists(folder.appendingPathComponent("plain.txt")), "converted source left input folder")
        let again = try await converter.convert(folder: folder)
        expect(output("document.pdf", in: again) == output("document.pdf", in: results), "receipt reuses retained PDF output")
        expect(output("scan.png", in: again) == output("scan.png", in: results), "receipt reuses retained OCR output")
    }

    static func namingAndSkips(_ root: URL) async throws {
        let folder = try directory("naming", in: root)
        let trash = try directory("naming-trash", in: root)
        let outside = try directory("outside", in: root)
        try write("USER MARKDOWN", "same.md", in: folder)
        try write("FIRST SOURCE", "same.txt", in: folder)
        try write("SECOND SOURCE", "same.text", in: folder)
        try write("EXISTING FALLBACK", "same.text.md", in: folder)
        try write("", "occupied.md", in: folder)
        try write("FULL SOURCE", "occupied.txt", in: folder)
        try write("UNSUPPORTED", "unknown.bin", in: folder)
        try write("ARCHIVE", "archive.zip", in: folder)
        try write("GENERATED", "linked-media-manifest.json", in: folder)
        try write("{\"schema_version\": 3, \"sources\": {}}", ".convert-manifest.json", in: folder)
        try write("HIDDEN", ".hidden.txt", in: folder)
        try write("HIDDEN TREE", "secret.txt", in: directory(".private", in: folder))
        try write("DEPENDENCY", "library.txt", in: directory("node_modules", in: folder))
        try write("VIRTUAL ENV", "library.txt", in: directory("venv", in: folder))
        try write("EXTERNAL", "external.txt", in: outside)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("external.txt"), withDestinationURL: outside.appendingPathComponent("external.txt"))
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("linked-folder"), withDestinationURL: outside)
        try write("NESTED", "note.txt", in: directory("subfolder", in: folder))
        let results = try await DistillConverter(trash: moveTo(trash)).convert(folder: folder)
        expect(output("same.txt", in: results)?.lastPathComponent == "same.txt.md", "existing Markdown gets extension fallback")
        expect(output("same.text", in: results)?.lastPathComponent == "same.text - Converted 2.md", "numbered collision fallback")
        expect(output("occupied.txt", in: results)?.lastPathComponent == "occupied.txt.md",
               "empty existing output is never accepted as proof of conversion")
        expect(try contents(folder.appendingPathComponent("same.md")) == "USER MARKDOWN", "existing Markdown is untouched")
        expect(status("same.md", in: results) == .skipped(.markdown), "Markdown is pass-through")
        expect(status("unknown.bin", in: results) == .skipped(.unsupported), "unsupported file is reported")
        expect(exists(folder.appendingPathComponent("unknown.bin")), "unsupported source remains untouched")
        expect(status("archive.zip", in: results) == .skipped(.unsupported), "archive requires a separate extractor")
        expect(status("linked-media-manifest.json", in: results) == .skipped(.generated), "generated manifests are skipped")
        expect(status("external.txt", in: results) == .skipped(.symbolicLink), "file symlink is skipped")
        expect(status("linked-folder", in: results) == .skipped(.symbolicLink), "directory symlink is not followed")
        expect(try contents(outside.appendingPathComponent("external.txt")) == "EXTERNAL", "symlink destination is unchanged")
        expect(!results.contains { $0.source.lastPathComponent == "library.txt" }, "dependency directories are skipped")
        expect(!results.contains { $0.source.lastPathComponent == "secret.txt" }, "hidden directories are skipped")
        expect(output("note.txt", in: results)?.deletingLastPathComponent().lastPathComponent == "subfolder",
               "nested output stays beside source")
    }

    static func integrations(_ root: URL) async throws {
        let folder = try directory("integration", in: root)
        let trash = try directory("integration-trash", in: root)
        let code = try directory("code", in: folder)
        try write("{\"manifest_version\": 3}", "manifest.json", in: code)
        try write("<script>const preserve = 123;</script>", "z-command.html", in: code)
        try write("<h1>Article</h1><p>Saved page</p>", "page.html", in: folder)
        try write("MEDIA FIXTURE", "recording.mp3", in: folder)
        let mhtml = """
            MIME-Version: 1.0
            Content-Type: multipart/related; boundary="saved-page"

            --saved-page
            Content-Type: text/html; charset=utf-8
            Content-Location: https://example.com/article
            Content-Transfer-Encoding: quoted-printable

            <p>caf=C3=A9 saved =
            page</p>
            --saved-page--
            """
        try write(mhtml, "archive.mhtml", in: folder)
        let unavailable = try await DistillConverter(trash: moveTo(trash)).convert(folder: folder)
        expect(status("page.html", in: unavailable) == .skipped(.htmlUnavailable), "HTML reports unavailable integration")
        expect(status("recording.mp3", in: unavailable) == .skipped(.mediaUnavailable), "media reports unavailable integration")
        try write("{\"manifest_version\": 3}", "manifest.json", in: code)
        let converter = DistillConverter(
            html: { html, base in
                guard !html.contains("const preserve") else { throw FixtureFailure.invalid }
                if base != nil {
                    guard html.contains("café saved page"), base?.host == "example.com" else { throw FixtureFailure.invalid }
                }
                return DistillConversion(markdown: "# Converted HTML\n\n" + html, retainSource: false)
            },
            media: { _ in DistillConversion(markdown: "TRANSCRIBED MEDIA 9153", retainSource: false) },
            trash: moveTo(trash))
        let results = try await converter.convert(folder: folder)
        expect(status("page.html", in: results) == .converted, "HTML closure plugs in")
        expect(try contents(code.appendingPathComponent("z-command.md")).contains("<script>const preserve = 123;</script>"),
               "HTML code is preserved before its project manifest is converted")
        expect(status("recording.mp3", in: results) == .converted, "media closure plugs in")
        expect(status("archive.mhtml", in: results) == .retained, "MHTML archive remains for embedded resources")
        expect(try contents(output("archive.mhtml", in: results)).contains("café saved page"),
               "MHTML decoded body reaches HTML seam")
        let base64 = "Content-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: base64\n\n"
            + Data("<p>BASE64 MIME 2468</p>".utf8).base64EncodedString()
        expect(try DistillMHTML.body(Data(base64.utf8)).text.contains("2468"), "base64 MIME decoding")
        do {
            _ = try DistillMHTML.body(Data(mhtml.replacingOccurrences(of: "--saved-page--", with: "").utf8))
            expect(false, "truncated MIME is rejected")
        } catch { expect(true, "truncated MIME is rejected") }
    }

    static func failureSafety(_ root: URL) async throws {
        let folder = try directory("failures", in: root)
        let trash = try directory("failures-trash", in: root)
        try write("", "empty.txt", in: folder)
        try write("NOT A PDF", "broken.pdf", in: folder)
        try write("NOT AN IMAGE", "broken.png", in: folder)
        try Data([0, 1, 255]).write(to: folder.appendingPathComponent("binary.txt"))
        try write("x", "empty.html", in: folder)
        try write("x", "failed.mp3", in: folder)
        let results = try await DistillConverter(
            html: { _, _ in DistillConversion(markdown: " \n", retainSource: false) },
            media: { _ in throw FixtureFailure.invalid }, trash: moveTo(trash)).convert(folder: folder)
        expect(results.count == 6, "all failed sources reported")
        expect(results.allSatisfy { if case .failed = $0.status { return exists($0.source) }; return false },
               "every failed conversion preserves its source")
        expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty, "failed conversions never call Trash")

        let changed = try directory("changed-source", in: root)
        try write("ORIGINAL", "document.html", in: changed)
        let source = changed.appendingPathComponent("document.html")
        let stale = try await DistillConverter(html: { _, _ in
            try Data("EDITED WHILE CONVERTING".utf8).write(to: source)
            return DistillConversion(markdown: "OLD RESULT", retainSource: false)
        }, trash: moveTo(trash)).convert(folder: changed)
        expect(isFailed(status("document.html", in: stale)) && exists(source), "source mutation invalidates async result")
        expect(!exists(changed.appendingPathComponent("document.md")), "stale result is never published")

        let retry = try directory("retry", in: root)
        try write("RETRY SOURCE 3541", "source.txt", in: retry)
        let denied = DistillConverter(trash: { _ in throw FixtureFailure.trashDenied })
        let failed = try await denied.convert(folder: retry)
        expect(isFailed(status("source.txt", in: failed)) && exists(retry.appendingPathComponent("source.txt")),
               "Trash failure keeps source and reports failure")
        let recovered = try await DistillConverter(trash: moveTo(trash)).convert(folder: retry)
        expect(status("source.txt", in: recovered) == .converted, "retry completes failed Trash operation")
        expect(output("source.txt", in: failed) == output("source.txt", in: recovered), "retry reuses verified output")

        let edited = try directory("edited-output", in: root)
        try write("ORIGINAL SOURCE", "source.txt", in: edited)
        let first = try await denied.convert(folder: edited)
        guard let firstOutput = output("source.txt", in: first) else { throw FixtureFailure.invalid }
        try Data("USER EDIT".utf8).write(to: firstOutput)
        let second = try await denied.convert(folder: edited)
        expect(try contents(firstOutput) == "USER EDIT", "edited output is never overwritten")
        expect(output("source.txt", in: second)?.lastPathComponent == "source.txt.md",
               "edited receipt output gets fresh destination")

        let unsafe = try directory("unsafe-receipt", in: root)
        try write("KEEP", "source.txt", in: unsafe)
        try FileManager.default.createSymbolicLink(
            at: unsafe.appendingPathComponent(DistillConverter.manifestName), withDestinationURL: firstOutput)
        do {
            _ = try await denied.convert(folder: unsafe)
            expect(false, "symlink manifest is rejected")
        } catch { expect(exists(unsafe.appendingPathComponent("source.txt")), "symlink manifest cannot authorize Trash") }
    }

    static func reviewRegressions(_ root: URL) async throws {
        let failures: [DistillConversion.Failure] = [
            .unreadable, .empty, .tooLarge, .sourceChanged, .outputChanged, .unsafePath, .noOutputName
        ]
        for failure in failures {
            expect(failure.localizedDescription == failure.errorDescription,
                   "conversion failures expose localized descriptions")
            expect(failure.localizedDescription.contains(" "), "failure description is a readable sentence")
        }
        let folder = try directory("linked-root-target", in: root)
        let trash = try directory("review-trash", in: root)
        let link = root.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        try write("RECOVER AFTER CRASH", "source.txt", in: folder)
        let source = folder.appendingPathComponent("source.txt")
        let expected = DistillConversion.literal("RECOVER AFTER CRASH", source: source).markdown
        try write(expected, "source.md", in: folder)
        let outside = try directory("linked-child-target", in: root)
        try write("KEEP OUTSIDE", "outside.txt", in: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("child"), withDestinationURL: outside)
        let results = try await DistillConverter(trash: moveTo(trash)).convert(folder: link)
        expect(status("source.txt", in: results) == .converted, "symlink job root is resolved")
        expect(output("source.txt", in: results)?.lastPathComponent == "source.md",
               "receipt-less matching output is reused")
        expect(!exists(folder.appendingPathComponent("source.txt.md")), "crash recovery creates no duplicate")
        expect(try contents(folder.appendingPathComponent("source.md")) == expected, "recovered output is unchanged")
        expect(exists(folder.appendingPathComponent(DistillConverter.manifestName)), "recovery saves a receipt")
        expect(status("child", in: results) == .skipped(.symbolicLink), "root resolution does not follow child links")
        expect(exists(outside.appendingPathComponent("outside.txt")), "child link destination remains untouched")
        try write("", "empty.txt", in: folder)
        let failed = try await DistillConverter(trash: moveTo(trash)).convert(folder: folder)
        expect(status("empty.txt", in: failed) == .failed(DistillConversion.Failure.empty.localizedDescription),
               "reported failure uses the localized description")
    }

    static func cancellation(_ root: URL) async throws {
        let folder = try directory("cancel", in: root)
        try write("HTML", "source.html", in: folder)
        let converter = DistillConverter(html: { _, _ in
            throw CancellationError()
        }, trash: { _ in throw FixtureFailure.invalid })
        do {
            _ = try await converter.convert(folder: folder)
            expect(false, "cancellation propagates")
        } catch is CancellationError { expect(true, "cancellation propagates") }
        expect(exists(folder.appendingPathComponent("source.html")), "cancellation preserves source")
        expect(!exists(folder.appendingPathComponent("source.md")), "cancellation publishes no output")
    }

    static func realTrash(_ root: URL) async throws {
        let folder = try directory("real-trash", in: root)
        let recovered = try directory("recovered-trash", in: root)
        try write("RECOVERABLE ORIGINAL 7432", "source.txt", in: folder)
        let converter = DistillConverter(trash: { source in
            let output = source.deletingPathExtension().appendingPathExtension("md")
            guard try Data(contentsOf: output).count > 0 else { throw FixtureFailure.invalid }
            var trashed: NSURL?
            try FileManager.default.trashItem(at: source, resultingItemURL: &trashed)
            guard let trashed else { throw FixtureFailure.invalid }
            try FileManager.default.moveItem(at: trashed as URL, to: recovered.appendingPathComponent("source.txt"))
        })
        let results = try await converter.convert(folder: folder)
        expect(status("source.txt", in: results) == .converted, "real FileManager Trash succeeds after output verification")
        expect(try contents(recovered.appendingPathComponent("source.txt")) == "RECOVERABLE ORIGINAL 7432",
               "trashed source is recoverable and unchanged")
    }

    nonisolated static func moveTo(_ folder: URL) -> DistillConverter.Trash {
        { source in
            let destination = folder.appendingPathComponent(UUID().uuidString + source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    static func directory(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ text: String, _ name: String, in folder: URL) throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }

    static func output(_ name: String, in results: [DistillConversion.Result]) -> URL? {
        results.first { $0.source.lastPathComponent == name }?.output
    }

    static func status(_ name: String, in results: [DistillConversion.Result]) -> DistillConversion.Status? {
        results.first { $0.source.lastPathComponent == name }?.status
    }

    static func contents(_ url: URL?) throws -> String {
        guard let url else { throw FixtureFailure.invalid }
        return try String(contentsOf: url, encoding: .utf8)
    }

    nonisolated static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func isFailed(_ status: DistillConversion.Status?) -> Bool {
        if case .failed = status { return true }
        return false
    }

    static func imageFixture() throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: 1000, height: 300, bitsPerComponent: 8, bytesPerRow: 4000,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw FixtureFailure.invalid }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 300))
        draw("ALPINE RECEIPT 7391", in: context)
        guard let image = context.makeImage() else { throw FixtureFailure.invalid }
        return image
    }

    static func pdfFixture(_ url: URL, scan: CGImage) throws {
        var box = CGRect(x: 0, y: 0, width: 1000, height: 300)
        guard let consumer = CGDataConsumer(url: url as CFURL),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw FixtureFailure.invalid }
        context.beginPDFPage(nil)
        draw("SELECTABLE DOCUMENT 4826", in: context)
        context.endPDFPage()
        context.beginPDFPage(nil)
        context.draw(scan, in: box)
        context.endPDFPage()
        context.closePDF()
    }

    static func draw(_ text: String, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        ]
        context.textPosition = CGPoint(x: 40, y: 150)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }
}
