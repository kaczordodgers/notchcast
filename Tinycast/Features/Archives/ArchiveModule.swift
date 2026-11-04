import Foundation
import Observation

@Observable @MainActor
final class ArchiveModule: NotchcastModule {
    let queue: ArchiveQueue
    private(set) var isRunning = false
    private(set) var toolURL: URL?
    private(set) var defaultApplicationFailure: String?

    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let locator: any ArchiveToolLocating
    @ObservationIgnored private let defaultApplications: any ArchiveDefaultApplicationSetting
    @ObservationIgnored private let application: URL
    @ObservationIgnored private var observationGeneration = 0
    @ObservationIgnored private var defaultApplicationTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var desiredDefaultApplication = false
    @ObservationIgnored private var appliedDefaultApplication = false
    @ObservationIgnored private var defaultApplicationMayBeClaimed = false

    init(
        preferences: NotchcastPreferences,
        locator: any ArchiveToolLocating = ArchiveToolLocator(),
        defaultApplications: any ArchiveDefaultApplicationSetting = ArchiveDefaultApplicationService(),
        application: URL = Bundle.main.bundleURL
    ) {
        self.preferences = preferences
        self.locator = locator
        self.defaultApplications = defaultApplications
        self.application = application
        appliedDefaultApplication = preferences.archiveHandlersClaimed
        defaultApplicationMayBeClaimed = preferences.archiveHandlersClaimed
        queue = ArchiveQueue(runner: ArchiveExtractionRunner(locator: locator))
    }

    isolated deinit {
        defaultApplicationTask?.cancel()
        recoveryTask?.cancel()
    }

    func start() {
        guard !isRunning, preferences.isOn(.archives) else { return }
        isRunning = true
        observationGeneration += 1
        let generation = observationGeneration
        recoveryTask = Task { [weak self] in
            do {
                let recovered = try await Self.recoverArchives()
                guard let self, !Task.isCancelled, self.isRunning,
                      self.observationGeneration == generation else { return }
                self.queue.addRecovered(recovered)
            } catch {
                guard let self, !Task.isCancelled, self.observationGeneration == generation else { return }
                self.defaultApplicationFailure = String(describing: error)
            }
        }
        observeDefaultApplication(generation: observationGeneration)
    }

    func stop() {
        recoveryTask?.cancel()
        isRunning = false
        observationGeneration += 1
        queue.stop()
        updateDefaultApplication()
    }

    func prepareForTermination() async {
        recoveryTask?.cancel()
        isRunning = false
        observationGeneration += 1
        queue.stop()
        requestDefaultApplication(preferences.isOn(.archives) && preferences.isOn(.archivesDefaultApp))
        await queue.waitUntilIdle()
        await defaultApplicationTask?.value
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard isRunning, preferences.isOn(.archives), url.isFileURL, ArchiveFormat.accepts(url) else { return false }
        queue.enqueue(url, mode: preferences.isOn(.archivesInPlace) ? .inPlace : .keepArchive)
        return true
    }

    func retry(_ id: UUID) {
        guard isRunning, preferences.isOn(.archives) else { return }
        queue.retry(id)
    }

    func refreshTool() async {
        let tool = await Self.locateTool(locator)
        guard !Task.isCancelled else { return }
        toolURL = tool
    }

    @concurrent private static func locateTool(_ locator: any ArchiveToolLocating) async -> URL? {
        locator.locate()
    }

    @concurrent private static func recoverArchives() async throws -> [ArchiveJob] {
        try ArchiveRecovery.recoverKnown()
    }

    private func observeDefaultApplication(generation: Int) {
        guard isRunning, observationGeneration == generation else { return }
        withObservationTracking(updateDefaultApplication) { [weak self] in
            Task { @MainActor [weak self] in self?.observeDefaultApplication(generation: generation) }
        }
    }

    private func updateDefaultApplication() {
        requestDefaultApplication(isRunning && preferences.isOn(.archives) && preferences.isOn(.archivesDefaultApp))
    }

    private func requestDefaultApplication(_ enabled: Bool) {
        desiredDefaultApplication = enabled
        guard defaultApplicationTask == nil,
              desiredDefaultApplication != appliedDefaultApplication
                || (!desiredDefaultApplication && defaultApplicationMayBeClaimed) else { return }
        defaultApplicationFailure = nil
        defaultApplicationTask = Task { [weak self] in
            defer { self?.defaultApplicationTask = nil }
            await self?.applyDefaultApplication()
        }
    }

    private func applyDefaultApplication() async {
        while desiredDefaultApplication != appliedDefaultApplication
            || (!desiredDefaultApplication && defaultApplicationMayBeClaimed) {
            let enabled = desiredDefaultApplication
            if enabled { defaultApplicationMayBeClaimed = true }
            do {
                try await defaultApplications.setEnabled(enabled, application: application)
                appliedDefaultApplication = enabled
                defaultApplicationMayBeClaimed = enabled
                preferences.archiveHandlersClaimed = enabled
                defaultApplicationFailure = nil
            } catch {
                appliedDefaultApplication = !desiredDefaultApplication
                if desiredDefaultApplication == enabled {
                    defaultApplicationFailure = String(localized: "Couldn’t change the default archive application.")
                    return
                }
            }
        }
    }
}
