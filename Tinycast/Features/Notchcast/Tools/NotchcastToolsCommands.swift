import Foundation
import Observation

@MainActor
final class NotchcastToolsCommands: NotchcastModule {
    enum Action: String, CaseIterable, Sendable {
        case convertFiles = "convert-files", compressVideo = "compress-video", makeGIF = "make-gif"
        case compressImage = "compress-image", resizeImage = "resize-image", extractText = "extract-text"
        case runHostCommand = "run-host-command", listCommands = "list-commands"

        var feature: NotchcastFeature {
            switch self {
            case .convertFiles: .convertFiles
            case .runHostCommand, .listCommands: .commandRunner
            default: .mediaTools
            }
        }

        var takesFiles: Bool { feature != .commandRunner }

        var name: String {
            switch self {
            case .convertFiles: String(localized: "Convert Files")
            case .compressVideo: String(localized: "Compress Video")
            case .makeGIF: String(localized: "Make GIF")
            case .compressImage: String(localized: "Compress Image")
            case .resizeImage: String(localized: "Resize Image")
            case .extractText: String(localized: "Extract Text")
            case .runHostCommand: String(localized: "Run Host Command")
            case .listCommands: String(localized: "List Commands")
            }
        }
    }

    private let preferences: NotchcastPreferences
    private let selection: () async throws -> [URL]
    private let post: (String) -> Void
    private let execute: @MainActor (Action, [URL], @escaping @MainActor () -> Bool) async throws -> Void
    private let refresh: () -> Void
    private var running = false
    private var tasks: [Action: Task<Void, Never>] = [:]
    private var generations: [Action: Int] = [:]
    private var identities: [Action: UUID] = [:]

    init(preferences: NotchcastPreferences, selection: @escaping () async throws -> [URL],
         post: @escaping (String) -> Void, refresh: @escaping () -> Void,
         execute: @escaping @MainActor (Action, [URL], @escaping @MainActor () -> Bool) async throws -> Void) {
        self.preferences = preferences
        self.selection = selection
        self.post = post
        self.refresh = refresh
        self.execute = execute
    }

    func isEnabled(_ action: Action) -> Bool { running && preferences.isOn(action.feature) }

    func start() {
        running = true
        for feature in [NotchcastFeature.convertFiles, .mediaTools, .commandRunner] { track(feature) }
    }

    func stop() {
        running = false
        identities.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        refresh()
    }

    private func track(_ feature: NotchcastFeature) {
        guard running else { return }
        withObservationTracking {
            _ = preferences.isOn(feature)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, running else { return }
                for action in Action.allCases where action.feature == feature
                    && generations[action] != preferences.revision(feature) {
                    tasks.removeValue(forKey: action)?.cancel()
                    identities.removeValue(forKey: action)
                }
                refresh()
                track(feature)
            }
        }
        refresh()
    }

    func perform(_ action: Action) {
        guard isEnabled(action) else { return }
        tasks[action]?.cancel()
        let id = UUID()
        let generation = preferences.revision(action.feature)
        generations[action] = generation
        identities[action] = id
        tasks[action] = Task { [weak self] in
            guard let self else { return }
            let valid: @MainActor @Sendable () -> Bool = { [weak self] in
                guard let self else { return false }
                return !Task.isCancelled && isEnabled(action) && identities[action] == id
                    && preferences.revision(action.feature) == generation
            }
            defer {
                if identities[action] == id { tasks[action] = nil; identities[action] = nil }
            }
            guard valid() else { return }
            do {
                let files = action.takesFiles ? try await selection() : []
                guard valid() else { return }
                guard !action.takesFiles || !files.isEmpty else {
                    post(String(localized: "No files selected in Finder.")); return
                }
                try await execute(action, files, valid)
            } catch {
                guard valid() else { return }
                post(error.localizedDescription)
            }
        }
    }

    func settle() async { for task in tasks.values { await task.value } }
}
