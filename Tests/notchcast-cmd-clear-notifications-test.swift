// notchcast-sources: Tinycast/Features/ClearNotifications/Model/*.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/Service/*.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/ClearNotificationsModule.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/ClearNotificationsModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
import AppKit
import Synchronization

enum NotchcastFeature { case clearNotifications }
@MainActor final class NotchcastPreferences {
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
@MainActor final class AppCore {}

@main
struct ClearNotificationsTests {
    @MainActor
    static func main() async throws {
        let calls = Mutex(0)
        precondition(!ClearNotificationsScript.source.contains("click at"))
        precondition(ClearNotificationsScript.source.contains("error \"notification-center-unavailable\" number -10001"))
        let runner = ClearNotificationsRunner { source in
            precondition(source == ClearNotificationsScript.source)
            calls.withLock { $0 += 1 }
            return " 3\n"
        }
        do {
            _ = try await runner.run(accessibilityGranted: false)
            preconditionFailure("Missing Accessibility must refuse")
        } catch let failure as ClearNotificationsFailure {
            precondition(failure == .accessibilityRequired)
        }
        precondition(calls.withLock { $0 } == 0, "No automation without the grant")
        let count = try await runner.run(accessibilityGranted: true)
        precondition(count == 3 && calls.withLock { $0 } == 1)
        let empty = ClearNotificationsRunner { _ in "0" }
        let emptyCount = try await empty.run(accessibilityGranted: true)
        precondition(emptyCount == 0)
        print("Verified cmd-clear-notifications: injected executor, grant refusal, empty and cleared counts")

        for invalid in ["", "-1", "1.5", "Cleared 3", "9223372036854775808"] {
            let invalidRunner = ClearNotificationsRunner { _ in invalid }
            do {
                _ = try await invalidRunner.run(accessibilityGranted: true)
                preconditionFailure("Invalid executor results must fail")
            } catch let failure as ClearNotificationsFailure {
                precondition(failure == .invalidResult)
            }
        }
        let errors: [(Int, ClearNotificationsFailure)] = [
            (-25211, .accessibilityRequired), (-1743, .automationRequired),
            (-10001, .notificationCenterUnavailable), (-10002, .unreadable),
            (-10003, .notificationsRemain), (-1719, .unreadable), (-1728, .unreadable),
            (-1712, .automationFailed(-1712)), (42, .automationFailed(42))
        ]
        for (code, expected) in errors {
            precondition(ClearNotificationsFailure.appleScript(code: code) == expected)
            let failing = ClearNotificationsRunner { _ in
                throw ClearNotificationsFailure.appleScript(code: code)
            }
            do {
                _ = try await failing.run(accessibilityGranted: true)
                preconditionFailure("Automation errors must propagate")
            } catch let failure as ClearNotificationsFailure {
                precondition(failure == expected)
            }
        }
        print("Verified cmd-clear-notifications: malformed results, permission errors, stale AX and remaining alerts")

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.run(accessibilityGranted: true)
        }
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled calls must refuse")
        } catch is CancellationError {}
        precondition(calls.withLock { $0 } == 1)
        let cancelDuringExecution = ClearNotificationsRunner { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return "5"
        }
        let stale = Task { try await cancelDuringExecution.run(accessibilityGranted: true) }
        do {
            _ = try await stale.value
            preconditionFailure("A result after cancellation must never publish")
        } catch is CancellationError {}
        let throwsCancellation = ClearNotificationsRunner { _ in throw CancellationError() }
        do {
            _ = try await throwsCancellation.run(accessibilityGranted: true)
            preconditionFailure("Executor cancellation must propagate")
        } catch is CancellationError {}
        print("Verified cmd-clear-notifications: cancellation before execution and after suspension")

        guard let script = NSAppleScript(source: ClearNotificationsScript.source) else {
            preconditionFailure("AppleScript must initialize")
        }
        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            preconditionFailure("AppleScript compile failed: \(String(describing: errorInfo))")
        }
        print("Verified cmd-clear-notifications: shipped AppleScript compiles without executing notifications")

        let entries = ClearNotificationsModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.clearNotifications] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === ClearNotificationsModule.shared)
        print("Verified cmd-clear-notifications: registration returns the shared module behind its switch")
    }
}
