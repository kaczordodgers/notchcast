import AppKit

@MainActor
enum RecordingCommands {
    nonisolated static let screen = NotchcastCommand(
        slug: "record-screen", name: String(localized: "Record Screen", table: "Notchcast"), sfSymbol: "record.circle",
        feature: .recording, isEnabled: { NotchcastPreferences.shared.isOn(.recording) },
        run: { RecordingModule.shared.recordScreen() })
    nonisolated static let area = NotchcastCommand(
        slug: "record-area", name: String(localized: "Record Area", table: "Notchcast"), sfSymbol: "viewfinder",
        feature: .recording, isEnabled: { NotchcastPreferences.shared.isOn(.recording) },
        run: { RecordingModule.shared.recordArea() })
    nonisolated static let pause = NotchcastCommand(
        slug: "pause-recording", name: String(localized: "Pause or Resume Recording", table: "Notchcast"), sfSymbol: "pause.circle",
        feature: .recording, isEnabled: {
            NotchcastPreferences.shared.isOn(.recording) && RecordingModule.shared.isCommandActive
        },
        run: { RecordingModule.shared.performRecordingCommand(.pause) })
    nonisolated static let stop = NotchcastCommand(
        slug: "stop-recording", name: String(localized: "Stop Recording", table: "Notchcast"), sfSymbol: "stop.circle",
        feature: .recording, isEnabled: {
            NotchcastPreferences.shared.isOn(.recording) && RecordingModule.shared.isCommandActive
        },
        run: { RecordingModule.shared.performRecordingCommand(.finish) })
}

extension RecordingModule {
    enum Command { case record(RecordingTarget), pause, finish }

    var isCommandActive: Bool { phase == .recording || phase == .paused }

    func recordScreen() {
        guard let displayID = NSScreen.underCursor?.displayID else {
            report(Self.failureMessage(RecordingTarget.Failure.targetUnavailable), true)
            return
        }
        performRecordingCommand(.record(.display(displayID)))
    }

    func recordArea() {
        do {
            guard enabled else { throw RecordingTarget.Failure.disabled }
            guard phase == .idle else { throw RecordingTarget.Failure.busy }
            try commandArea.start { [weak self] selection in
                guard let self, self.enabled, let selection else { return }
                self.performRecordingCommand(.record(.area(selection.rect)))
            }
        } catch { report(Self.failureMessage(error), true) }
    }

    func performRecordingCommand(_ command: Command) {
        commandTask = Task { [weak self] in
            await self?.executeRecordingCommand(command)
        }
    }

    func executeRecordingCommand(_ command: Command) async {
        do {
            switch command {
            case .record(let target): try await record(target)
            case .pause: try setPaused(phase != .paused)
            case .finish:
                await finishAndReport()
            }
        } catch is CancellationError {
        } catch { report(Self.failureMessage(error), true) }
    }
}
