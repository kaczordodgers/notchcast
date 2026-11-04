import Foundation
import Observation

@MainActor
@Observable
final class EditorDocumentSession {
    let id = UUID()
    private(set) var url: URL
    private(set) var source: String
    private(set) var saved: EditorDocumentSnapshot
    private(set) var externalVersion: EditorDocumentSnapshot?
    private(set) var failure: Error?
    private(set) var isBusy = false
    private(set) var isEnabled = false
    var brainDump = false
    var staysOnTop = false
    var rendersMarkdown: Bool
    private var generation = 0
    private var lifecycle = 0
    @ObservationIgnored private var operation: Task<EditorDocumentSnapshot, Error>?
    @ObservationIgnored private var autosave: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var presenter: EditorFilePresenter?
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var needsRefresh = false

    init(url: URL, snapshot: EditorDocumentSnapshot, rendersMarkdown: Bool) {
        self.url = url
        source = snapshot.source
        saved = snapshot
        self.rendersMarkdown = rendersMarkdown
    }

    isolated deinit {
        autosave?.cancel()
        refreshTask?.cancel()
        operation?.cancel()
        presenter?.stop()
    }

    var isDirty: Bool { !source.utf8.elementsEqual(saved.source.utf8) }

    var editorInput: NoteEditorInput {
        NoteEditorInput(id: NoteID(rawValue: id.uuidString), source: source, epoch: generation)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        lifecycle += 1
        isEnabled = enabled
        if enabled {
            watch()
            requestRefresh()
        } else {
            autosave?.cancel()
            refreshTask?.cancel()
            presenter?.stop()
            presenter = nil
        }
    }

    @discardableResult
    func edit(_ next: String) -> Bool {
        guard isEnabled, EditorTextPolicy.accepts(next, after: source, brainDump: brainDump) else { return false }
        source = next
        scheduleAutosave()
        return true
    }

    func plan(_ action: NoteEditAction, selection: NSRange) -> NoteEditPlan? {
        guard rendersMarkdown else { return nil }
        return NoteMarkdownEditing.plan(
            action, source: source, selection: selection, markdown: NoteMarkdownParser.parse(source))
    }

    func save() async throws {
        guard isEnabled else { throw EditorFailure.disabled }
        guard isDirty else { return }
        guard externalVersion == nil else { throw EditorFailure.externalChange }
        let draft = source
        let destination = url
        let baseline = saved
        do {
            saved = try await perform { try await EditorDocumentRepository.save(draft, to: destination, expecting: baseline) }
            failure = nil
            scheduleAutosave()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failure = error
            if error as? EditorFailure == .externalChange || error as? EditorFailure == .missingFile {
                requestRefresh()
            }
            throw error
        }
    }

    func refresh() async throws {
        guard isEnabled else { throw EditorFailure.disabled }
        let location = url
        let requestLifecycle = lifecycle
        do {
            let next = try await perform { try await EditorDocumentRepository.load(location) }
            try Task.checkCancellation()
            guard isEnabled, lifecycle == requestLifecycle else { return }
            guard next.bytes != saved.bytes else {
                externalVersion = nil
                failure = nil
                scheduleAutosave()
                return
            }
            if isDirty {
                externalVersion = next
                failure = EditorFailure.externalChange
                autosave?.cancel()
            } else {
                install(next)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failure = error
            throw error
        }
    }

    func reloadExternalVersion() throws {
        guard isEnabled else { throw EditorFailure.disabled }
        guard operation == nil else { throw EditorFailure.busy }
        guard let externalVersion else { return }
        install(externalVersion)
    }

    func saveMyChanges() async throws {
        guard isEnabled else { throw EditorFailure.disabled }
        guard let externalVersion else { return try await save() }
        let draft = source
        let destination = url
        do {
            saved = try await perform {
                try await EditorDocumentRepository.save(draft, to: destination, expecting: externalVersion)
            }
            self.externalVersion = nil
            failure = nil
            scheduleAutosave()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failure = error
            requestRefresh()
            throw error
        }
    }

    func saveAs(_ destination: URL) async throws {
        guard isEnabled else { throw EditorFailure.disabled }
        let markdown = try EditorDocumentRepository.kind(of: destination)
        let draft = source
        let format = saved
        do {
            let next = try await perform {
                try await EditorDocumentRepository.create(draft, at: destination, format: format)
            }
            presenter?.stop()
            url = destination.standardizedFileURL
            rendersMarkdown = markdown
            saved = next
            externalVersion = nil
            failure = nil
            if isEnabled { watch() }
            scheduleAutosave()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failure = error
            throw error
        }
    }

    func flush() async throws {
        autosave?.cancel()
        await waitUntilIdle()
        try Task.checkCancellation()
        if isDirty { try await save() }
    }

    func requestRefresh() {
        guard isEnabled else { return }
        needsRefresh = true
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                refreshTask = nil
                if isEnabled && needsRefresh { requestRefresh() }
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
                while needsRefresh {
                    needsRefresh = false
                    await waitUntilIdle()
                    try Task.checkCancellation()
                    try await refresh()
                }
            } catch is CancellationError {
            } catch {
                failure = error
            }
        }
    }

    private func watch() {
        presenter = EditorFilePresenter(url: url) { [weak self] in
            Task { @MainActor [weak self] in self?.requestRefresh() }
        }
    }

    private func install(_ next: EditorDocumentSnapshot) {
        source = next.source
        saved = next
        externalVersion = nil
        failure = nil
        generation += 1
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        guard isEnabled, isDirty, externalVersion == nil, failure == nil else { return }
        autosave = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                await self?.waitUntilIdle()
                try Task.checkCancellation()
                try await self?.save()
            } catch is CancellationError {
            } catch {
                self?.failure = error
            }
        }
    }

    private func waitUntilIdle() async {
        guard isBusy else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func perform(
        _ work: @escaping @Sendable () async throws -> EditorDocumentSnapshot
    ) async throws -> EditorDocumentSnapshot {
        guard operation == nil else { throw EditorFailure.busy }
        try Task.checkCancellation()
        let task = Task { try await work() }
        operation = task
        isBusy = true
        defer {
            operation = nil
            isBusy = false
            let waiters = idleWaiters
            idleWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
