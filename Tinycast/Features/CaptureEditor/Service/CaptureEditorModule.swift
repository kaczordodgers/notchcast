import CoreGraphics
import Foundation

@MainActor
final class CaptureEditorModule: NotchcastModule {
    enum Failure: Error { case disabled, noDocument }
    private(set) var isRunning = false
    private(set) var identity = UUID()
    var document: CaptureEditorDocument? {
        didSet { identity = UUID() }
    }

    func start() { isRunning = true }
    func stop() { isRunning = false; document = nil; identity = UUID() }

    func open(_ image: CGImage) throws {
        guard isRunning else { throw Failure.disabled }
        identity = UUID()
        document = CaptureEditorDocument(image: image)
    }

    func copy(using writer: (CGImage) throws -> Void) async throws {
        guard isRunning else { throw Failure.disabled }
        guard let document else { throw Failure.noDocument }
        let operation = identity
        let result = try await Self.render(document)
        try Task.checkCancellation()
        guard isRunning, identity == operation else { throw CancellationError() }
        try writer(result)
    }

    @concurrent
    private static func render(_ document: CaptureEditorDocument) async throws -> CGImage {
        try Task.checkCancellation()
        return try CaptureEditorRender.flatten(document)
    }
}
