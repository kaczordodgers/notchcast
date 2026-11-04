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

    init(mode: Mode = .auto, confirmed: @escaping (Mode) -> Void = { _ in },
         failed: @escaping () -> Void = {},
         runner: @escaping @Sendable (RootContract.Command) async throws -> Void = {
        _ = try await RootHelperClient().run($0)
    }) {
        self.runner = runner
        self.mode = mode
        self.confirmed = confirmed
        self.failed = failed
    }

    func set(_ requested: Mode) {
        enqueue(Request(mode: requested))
    }

    private func enqueue(_ request: Request) {
        guard request.mode != (pending?.mode ?? applying?.mode ?? mode) else { return }
        pending = request
        guard worker == nil else { return }
        worker = Task { [self] in
            while let next = pending {
                pending = nil
                applying = next
                do {
                    try await runner(next.mode.command)
                    mode = next.mode
                    if !next.preservePreference { confirmed(next.mode) }
                    unavailable = false
                } catch {
                    unavailable = true
                    if !next.silent { failed() }
                    if next.silent { confirmed(.auto) }
                    if next.mode != .auto {
                        // Restore before accepting another manual request after an uncertain result.
                        do {
                            try await runner(.fansAuto)
                            mode = .auto
                            confirmed(.auto)
                        } catch { pending = nil }
                    }
                }
            }
            worker = nil
            applying = nil
        }
    }

    func restore(preservingPreference: Bool = false, silently: Bool = false) {
        guard mode != .auto || pending != nil || worker != nil else { return }
        enqueue(Request(mode: .auto, preservePreference: preservingPreference, silent: silently))
    }

    func waitUntilIdle() async { await worker?.value }
}
