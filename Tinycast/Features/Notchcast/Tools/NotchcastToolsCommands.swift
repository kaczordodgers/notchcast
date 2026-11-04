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
    private let selection: () throws -> [URL]
    private let post: (String) -> Void
    private let execute: @MainActor (Action, [URL], @escaping @MainActor () -> Bool) async throws -> Void
    private let refresh: () -> Void
    private var running = false
    private var tasks: [Action: Task<Void, Never>] = [:]
    private var identities: [Action: UUID] = [:]

    init(preferences: NotchcastPreferences, selection: @escaping () throws -> [URL],
         post: @escaping (String) -> Void, refresh: @escaping () -> Void,
         execute: @escaping @MainActor (Action, [URL], @escaping @MainActor () -> Bool) async throws -> Void) {
        self.preferences = preferences
        self.selection = selection
        self.post = post
        self.refresh = refresh
        self.execute = execute
    }

    func isEnabled(_ action: Action) -> Bool { running && preferences.isOn(action.feature) }

    func start() { running = true; track() }

    func stop() {
        running = false
        identities.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        refresh()
    }

    private func track() {
        guard running else { return }
        withObservationTracking {
            for feature in [NotchcastFeature.convertFiles, .mediaTools, .commandRunner, .downloads] {
                _ = preferences.isOn(feature)
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, running else { return }
                for action in Action.allCases where !isEnabled(action) {
                    tasks.removeValue(forKey: action)?.cancel()
                    identities.removeValue(forKey: action)
                }
                refresh()
                track()
            }
        }
        refresh()
    }

    func perform(_ action: Action) {
        guard isEnabled(action) else { return }
        tasks[action]?.cancel()
        let id = UUID()
        identities[action] = id
        tasks[action] = Task { [weak self] in
            guard let self else { return }
            let valid: @MainActor @Sendable () -> Bool = { [weak self] in
                guard let self else { return false }
                return !Task.isCancelled && isEnabled(action) && identities[action] == id
            }
            defer {
                if identities[action] == id { tasks[action] = nil; identities[action] = nil }
            }
            guard valid() else { return }
            do {
                let files = action.takesFiles ? try selection() : []
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
