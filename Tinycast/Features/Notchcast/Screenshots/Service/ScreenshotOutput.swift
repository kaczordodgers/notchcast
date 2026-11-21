import Foundation
import ImageIO

/// What a finished capture says on the island.
enum ScreenshotNotices {
    /// The editor's own Copy and Save notices; a limit or a partial run says so instead, a little longer.
    static func scrolling(_ ending: ScrollStitchSession.Ending, saved: URL?) -> IslandNotice {
        let reason: String? = switch ending {
        case .limitedByHeight:
            String(localized: "Scrolling capture reached the 20,000 pixel limit.", table: "NotchcastScreenshots")
        case .limitedByGuard: String(localized: "Scrolling capture stopped at its limit.", table: "NotchcastScreenshots")
        case .partial:
            String(localized: "Kept the part before the page changed.", table: "NotchcastScreenshots")
        case .success, .failed: nil
        }
        var notice = saved.map(self.saved) ?? copied
        if let reason {
            notice.text = reason
            notice.seconds = IslandNotice.failureSeconds
        }
        return notice
    }

    static var copied: IslandNotice {
        IslandNotice(id: "screenshot.copied", symbol: "camera",
                     text: String(localized: "Copied", table: "NotchcastScreenshots"))
    }

    static func saved(_ url: URL) -> IslandNotice {
        let name = url.deletingLastPathComponent().lastPathComponent
        return IslandNotice(id: "screenshot.saved", symbol: "camera",
                            text: String(localized: "Saved to \(name)", table: "NotchcastScreenshots"))
    }
}

/// Encoding and writing off the main actor.
enum ScreenshotFiles {
    @concurrent
    static func png(_ image: CGImage, scale: CGFloat) async throws -> Data {
        do {
            return try AnnotationRenderer.png(image, scale: scale)
        } catch {
            throw ScreenshotRequest.Failure.encodingFailed
        }
    }

    @concurrent
    static func render(_ document: AnnotationDocument) async throws -> Data {
        do {
            return try AnnotationRenderer.png(document.finished())
        } catch {
            throw ScreenshotRequest.Failure.encodingFailed
        }
    }

    @concurrent
    static func decode(_ data: Data) async -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// Save As writes where the save panel pointed, which already asked before replacing a file.
    @concurrent
    static func write(_ data: Data, to url: URL) async throws -> URL {
        try data.write(to: url, options: .atomic)
        return url
    }

    @concurrent
    static func save(_ data: Data, in folder: URL, date: Date, timeZone: TimeZone) async throws -> URL {
        var collision = 0
        while true {
            try Task.checkCancellation()
            let url = folder.appending(
                path: ScreenshotFileName.name(date: date, timeZone: timeZone, collision: collision))
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                collision += 1
            }
        }
    }
}
