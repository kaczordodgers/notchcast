import AppKit
import Observation

@MainActor @Observable
final class ScreenTextModule: NotchcastModule {
    typealias Recognize = @Sendable (CaptureAreaSelection, Bool) async throws -> ScreenTextResult
    nonisolated static let removeLineBreaksKey = "screenText.removeLineBreaks"
    var removeLineBreaks: Bool {
        didSet {
            defaults.set(removeLineBreaks, forKey: Self.removeLineBreaksKey)
            cancel()
        }
    }
    private let defaults: UserDefaults
    private let area: CaptureAreaService
    private let recognize: Recognize
    private let write: (String) -> Bool
    private var enabled = false
    private var task: Task<Void, Never>?

    init(
        defaults: UserDefaults = NotchcastIdentity.current.defaults,
        area: CaptureAreaService = CaptureAreaService(),
        recognize: @escaping Recognize = {
            try await ScreenTextService.recognize(selection: $0, removeLineBreaks: $1)
        },
        write: @escaping (String) -> Bool = {
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString($0, forType: .string)
        }
    ) {
        self.defaults = defaults
        self.area = area
        self.recognize = recognize
        self.write = write
        removeLineBreaks = defaults.bool(forKey: Self.removeLineBreaksKey)
    }

    func start() { enabled = true }
    func stop() { enabled = false; cancel() }

    func capture(report: @escaping (String) -> Void) {
        guard enabled else { return }
        cancel()
        do {
            try area.start { [weak self] selection in
                guard let self, self.enabled, let selection else { return }
                self.task = Task { [weak self, recognize, removeLineBreaks] in
                    do {
                        let result = try await recognize(selection, removeLineBreaks)
                        try Task.checkCancellation()
                        guard let self, self.enabled else { return }
                        guard self.write(result.content) else { throw ScreenTextService.Failure.clipboardWriteFailed }
                    } catch is CancellationError {
                    } catch {
                        guard !Task.isCancelled else { return }
                        report(Self.failureMessage(error))
                    }
                }
            }
        } catch { report(Self.failureMessage(error)) }
    }

    private func cancel() { task?.cancel(); task = nil; area.stop() }
    isolated deinit { task?.cancel() }

    static func failureMessage(_ error: any Error) -> String {
        if case ScreenTextService.Failure.noContent = error {
            return String(localized: "No text found in the selected area.", table: "Notchcast")
        }
        return (CaptureFailure(error) ?? .captureFailed).message
    }
}
