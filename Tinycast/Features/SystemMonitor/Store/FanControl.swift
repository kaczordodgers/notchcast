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
    @ObservationIgnored private var pending: Mode?
    @ObservationIgnored private var applying: Mode?
    @ObservationIgnored private var worker: Task<Void, Never>?

    init(runner: @escaping @Sendable (RootContract.Command) async throws -> Void = {
        _ = try await RootHelperClient().run($0)
    }) {
        self.runner = runner
    }

    func set(_ requested: Mode) {
        guard requested != (pending ?? applying ?? mode) else { return }
        pending = requested
        guard worker == nil else { return }
        worker = Task { [self] in
            while let next = pending {
                pending = nil
                applying = next
                do {
                    try await runner(next.command)
                    mode = next
                    unavailable = false
                } catch {
                    unavailable = true
                    if next != .auto {
                        // Restore before accepting another manual request after an uncertain result.
                        do { try await runner(.fansAuto); mode = .auto } catch { pending = nil }
                    }
                }
            }
            worker = nil
            applying = nil
        }
    }

    func restore() {
        guard mode != .auto || pending != nil || worker != nil else { return }
        set(.auto)
    }

    func waitUntilIdle() async { await worker?.value }
}
