import Foundation

@MainActor
final class CaptureTrimmerModule: NotchcastModule {
    private(set) var enabled = false

    static func live() -> CaptureTrimmerModule { CaptureTrimmerModule() }

    func start() { enabled = true }
    func stop() { enabled = false }
}
