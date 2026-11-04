import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class EditorCoordinator: NotchcastModule {
    private(set) var documents: [EditorDocumentSession] = []
    let editorPreferences: EditorPreferences
    private let preferences: NotchcastPreferences
    private var isRunning = false
    private var generation = 0

    init(preferences: NotchcastPreferences, editorPreferences: EditorPreferences) {
        self.preferences = preferences
        self.editorPreferences = editorPreferences
    }

    func start() {
        guard !isRunning else { return }
        generation += 1
        isRunning = true
        observeAvailability()
    }

    func stop() {
        generation += 1
        isRunning = false
        for document in documents { document.setEnabled(false) }
    }

    func open(_ url: URL) async throws -> EditorDocumentSession {
        let markdown = try EditorDocumentRepository.kind(of: url)
        guard isRunning, preferences.isOn(markdown ? .markdownFiles : .plainTextFiles) else {
            throw EditorFailure.disabled
        }
        let location = url.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = documents.first(where: { $0.url == location }) { return existing }
        let requestGeneration = generation
        let snapshot = try await EditorDocumentRepository.load(location)
        try Task.checkCancellation()
        guard isRunning, generation == requestGeneration,
            preferences.isOn(markdown ? .markdownFiles : .plainTextFiles)
        else {
            throw EditorFailure.disabled
        }
        if let existing = documents.first(where: { $0.url == location }) { return existing }
        let document = EditorDocumentSession(url: location, snapshot: snapshot, rendersMarkdown: markdown)
        documents.append(document)
        document.setEnabled(true)
        return document
    }

    func close(_ document: EditorDocumentSession, discardChanges: Bool = false) throws {
        guard !document.isBusy else { throw EditorFailure.busy }
        guard discardChanges || !document.isDirty else { throw EditorFailure.unsavedChanges }
        document.setEnabled(false)
        documents.removeAll { $0 === document }
    }

    func newDocument(at url: URL) async throws -> EditorDocumentSession {
        let markdown = try EditorDocumentRepository.kind(of: url)
        guard isRunning, preferences.isOn(markdown ? .markdownFiles : .plainTextFiles) else {
            throw EditorFailure.disabled
        }
        let format = try EditorDocumentSnapshot(bytes: Data())
        _ = try await EditorDocumentRepository.create("", at: url, format: format)
        return try await open(url)
    }

    func saveAs(_ document: EditorDocumentSession, to url: URL) async throws {
        let markdown = try EditorDocumentRepository.kind(of: url)
        guard isRunning, preferences.isOn(markdown ? .markdownFiles : .plainTextFiles) else {
            throw EditorFailure.disabled
        }
        try await document.saveAs(url)
    }

    func flush() async throws {
        for document in documents where document.isEnabled { try await document.flush() }
    }

    func flushForTermination() async {
        for document in documents where document.isEnabled {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "editor")
            do {
                let recovery = try await EditorRecoveryService.flush(
                    document, directory: AppPaths.applicationSupport().appendingPathComponent("EditorRecovery"))
                if let recovery {
                    logger.error("Document recovered at termination: \(recovery.path, privacy: .private)")
                }
            } catch {
                logger.error("Document recovery failed at termination: \(error.localizedDescription, privacy: .private)")
            }
        }
        stop()
    }

    private func observeAvailability() {
        guard isRunning else { return }
        withObservationTracking {
            for document in documents {
                let markdown = (try? EditorDocumentRepository.kind(of: document.url)) ?? false
                document.setEnabled(preferences.isOn(markdown ? .markdownFiles : .plainTextFiles))
            }
            _ = preferences.isOn(.markdownFiles)
            _ = preferences.isOn(.plainTextFiles)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAvailability() }
        }
    }
}
