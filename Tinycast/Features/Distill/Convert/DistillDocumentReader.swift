import AppKit
import Foundation
import PDFKit

nonisolated enum DistillDocumentReader {
    static func office(_ source: URL) throws -> DistillConversion {
        let type: NSAttributedString.DocumentType
        switch source.pathExtension.lowercased() {
        case "doc": type = .docFormat
        case "docx": type = .officeOpenXML
        case "odt": type = .openDocument
        default: type = .rtf
        }
        let data = try Data(contentsOf: source)
        let text = try NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil).string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DistillConversion.Failure.empty
        }
        return .literal(text, source: source, retainSource: true)
    }

    static func pdf(_ source: URL) async throws -> DistillConversion {
        guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else {
            throw DistillConversion.Failure.unreadable
        }
        var sections: [String] = []
        var byteCount = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw DistillConversion.Failure.unreadable }
            var text = autoreleasepool { page.string ?? "" }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let image = autoreleasepool(invoking: { render(page) }) else {
                    throw DistillConversion.Failure.unreadable
                }
                text = try await DistillOCR.recognize(image)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DistillConversion.Failure.empty
                }
                text = "Automatic OCR transcription; compare unclear wording with the original page.\n\n" + text
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DistillConversion.Failure.empty
            }
            let section = "## Page \(index + 1)\n\n" + DistillConversion.literal(text, source: source).markdown
            byteCount += section.utf8.count
            guard byteCount <= DistillFileAccess.maximumBytes else { throw DistillConversion.Failure.tooLarge }
            sections.append(section)
        }
        // PDFKit cannot certify that text extraction preserved drawings, forms or embedded assets.
        return DistillConversion(markdown: sections.joined(separator: "\n\n") + "\n")
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, 4096 / max(bounds.width, bounds.height), sqrt(4_194_304 / bounds.width / bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(reference.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        return context.makeImage()
    }
}
