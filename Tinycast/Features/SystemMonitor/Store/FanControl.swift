import Foundation
import Observation

@MainActor
@Observable
final class FanControl {
    enum Mode: String, CaseIterable, Sendable {
        case auto, medium, max

        var command: RootContract.Command {
            switch self {
            case .auto: .fansAuto
            case .medium: .fansMedium
            case .max: .fansMax
            }
        }
    }

    private(set) var mode: Mode = .auto
    private(set) var unavailable = false
    @ObservationIgnored private let runner: @Sendable (RootContract.Command) async throws -> Void
    private struct Request {
        var mode: Mode
        var preservePreference = false
        var silent = false
    }
    @ObservationIgnored private var pending: Request?
    @ObservationIgnored private var applying: Request?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let confirmed: (Mode) -> Void
    @ObservationIgnored private let failed: () -> Void
    @ObservationIgnored private var journal: FanOwnershipJournal
    @ObservationIgnored private let persist: (Data) -> Void
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var afterRepair: Request?
    private(set) var failure: Error?

    init(confirmed: @escaping (Mode) -> Void = { _ in },
         failed: @escaping () -> Void = {}, journalData: Data? = nil,
         persist: @escaping (Data) -> Void = { _ in },
         runner: @escaping @Sendable (RootContract.Command) async throws -> Void = {
        _ = try await RootHelperClient().run($0)
    }) {
        self.runner = runner
        self.confirmed = confirmed
        self.failed = failed
        self.persist = persist
        journal = journalData.flatMap { try? JSONDecoder().decode(FanOwnershipJournal.self, from: $0) }
            ?? FanOwnershipJournal()
        unavailable = journal.failures > 0
        if unavailable { failure = RootHelperClient.Failure.executionFailed(70) }
    }

    func set(_ requested: Mode) {
        enqueue(Request(mode: requested))
    }

    isolated deinit { retry?.cancel() }

    private func enqueue(_ request: Request) {
        if request.mode != .auto && journal.intent == "auto" && journal.failures > 0 {
            afterRepair = request
            enqueue(Request(mode: .auto, preservePreference: true, silent: true))
            return
        }
        guard request.mode != (pending?.mode ?? applying?.mode ?? mode)
            || (request.mode == .auto && journal.needsUndo && worker == nil) else { return }
        retry?.cancel()
        pending = request
        guard worker == nil else { return }
        worker = Task { [self] in
            while let next = pending {
                pending = nil
                applying = next
                if journal.intent == next.mode.rawValue && !journal.mayRetry(now: .now) { break }
                journal.begin(next.mode.rawValue)
                saveJournal()
                do {
                    try await runner(next.mode.command)
                    journal.succeed(next.mode.rawValue)
                    saveJournal()
                    if pending == nil || pending?.mode == next.mode {
                        mode = next.mode
                        if !next.preservePreference { confirmed(next.mode) }
                    }
                    unavailable = false
                    failure = nil
                    if next.mode == .auto, pending == nil, let deferred = afterRepair {
                        pending = deferred
                        afterRepair = nil
                    }
                } catch {
                    failure = error
                    journal.fail(now: .now)
                    if next.mode == .auto,
                       case RootHelperClient.Failure.executionFailed(69) = error {
                        journal.succeed("auto")
                    }
                    saveJournal()
                    unavailable = true
                    if !next.silent { failed() }
                    if next.mode != .auto {
                        // Restore before accepting another manual request after an uncertain result.
                        do {
                            journal.begin("auto")
                            saveJournal()
                            try await runner(.fansAuto)
                            mode = .auto
                            journal.succeed("auto")
                            saveJournal()
                            if !next.preservePreference && pending?.preservePreference != true {
                                confirmed(.auto)
                            }
                        } catch {
                            failure = error
                            if case RootHelperClient.Failure.executionFailed(69) = error {
                                journal.succeed("auto")
                            } else {
                                journal.fail(now: .now)
                            }
                            saveJournal()
                            pending = nil
                        }
                    }
                }
            }
            worker = nil
            applying = nil
            if journal.needsUndo && journal.failures > 0 && journal.failures < 6 {
                retry?.cancel()
                let delay = max(0, journal.retryAt?.timeIntervalSinceNow ?? 60)
                retry = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    self?.enqueue(Request(mode: .auto, preservePreference: true, silent: true))
                }
            }
        }
    }

    func restore(preservingPreference: Bool = false, silently: Bool = false) {
        afterRepair = nil
        guard mode != .auto || journal.needsUndo || pending != nil || worker != nil else { return }
        enqueue(Request(mode: .auto, preservePreference: preservingPreference, silent: silently))
    }

    func waitUntilIdle() async { await worker?.value }

    private func saveJournal() {
        if let data = try? JSONEncoder().encode(journal) { persist(data) }
    }
}
