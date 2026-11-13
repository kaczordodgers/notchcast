import Foundation
import ScreenCaptureKit
import Vision

enum ScreenTextService {
    enum Failure: CaptureFailureConvertible {
        case displayUnavailable, noContent, clipboardWriteFailed

        var captureFailure: CaptureFailure? {
            switch self {
            case .clipboardWriteFailed: .clipboardFailed
            case .displayUnavailable: .areaUnavailable
            case .noContent: nil
            }
        }
    }

    @concurrent
    static func recognize(
        selection: CaptureAreaSelection, removeLineBreaks: Bool = false,
        content: @Sendable () async throws -> ([SCDisplay], [SCRunningApplication]) = {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return (content.displays, content.applications)
        }
    ) async throws -> ScreenTextResult {
        try Task.checkCancellation()
        let (displays, applications) = try await content()
        try Task.checkCancellation()
        guard let display = displays.first(where: { $0.displayID == selection.displayID })
        else { throw Failure.displayUnavailable }
        let ownApplications = applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
                || $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = selection.sourceRect
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = max(1, Int(ceil(selection.rect.width * scale)))
        configuration.height = max(1, Int(ceil(selection.rect.height * scale)))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)
        return try await recognize(image: image, removeLineBreaks: removeLineBreaks)
    }

    @concurrent
    static func recognize(
        image: CGImage, removeLineBreaks: Bool = false
    ) async throws -> ScreenTextResult {
        try Task.checkCancellation()
        let barcodes = try await DetectBarcodesRequest().perform(on: image)
        try Task.checkCancellation()
        let payloads = barcodes.filter { $0.payloadString?.isEmpty == false }
        if let barcode = payloads.first(where: { $0.symbology == .qr }) ?? payloads.first,
            let payload = barcode.payloadString {
            return ScreenTextResult(content: payload, kind: barcode.symbology == .qr ? .qrCode : .barcode)
        }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        var content = ""
        var previous: RecognizedTextObservation?
        for observation in observations {
            guard let line = observation.topCandidates(1).first?.string else { continue }
            if let previous {
                let gap = previous.boundingBox.cgRect.minY - observation.boundingBox.cgRect.maxY
                content += gap > previous.boundingBox.cgRect.height * 0.8 ? "\n\n" : "\n"
            }
            content += line
            previous = observation
        }
        guard !content.isEmpty else { throw Failure.noContent }
        return ScreenTextResult(
            content: removeLineBreaks ? ScreenTextResult.removingLineBreaks(content) : content, kind: .text)
    }
}
