// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Clean/*/*.swift
// notchcast-sources: Tinycast/Features/Clean/CleanCoordinator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift
import Foundation
import Synchronization

final class WiringFake: Sendable {
    struct State {
        var scans = 0
        var trashed: [URL] = []
        var suspended = false
        var continuation: CheckedContinuation<Void, Never>?
        var optimized: [CleanOptimizeTask] = []
    }
    let state = Mutex(State())
    let root: URL
    let reviewed: URL
    let unreviewed: URL
    let trash: URL

    init(_ root: URL) throws {
        self.root = root
        reviewed = root.appendingPathComponent("reviewed")
        unreviewed = root.appendingPathComponent("unreviewed")
        trash = root.appendingPathComponent("fake-trash")
        try FileManager().createDirectory(at: trash, withIntermediateDirectories: false)
        try Data("reviewed".utf8).write(to: reviewed)
        try Data("sentinel".utf8).write(to: unreviewed)
    }

    var transport: CleanCoordinator.Transport {
        .init(scan: { [self] feature, _ in
            let suspend = state.withLock { $0.scans += 1; return $0.suspended }
            if feature == .cleanOptimize {
                return .init(items: CleanOptimizeTask.allCases.map {
                    .init(id: root.appendingPathComponent($0.rawValue), size: nil)
                }) { paths in
                    self.state.withLock { state in
                        state.optimized += paths.compactMap { CleanOptimizeTask(rawValue: $0.lastPathComponent) }
                    }
                }
            }
            if suspend {
                await withCheckedContinuation { continuation in
                    state.withLock { $0.continuation = continuation }
                }
            }
            return .init(items: [.init(id: reviewed, size: 8), .init(id: unreviewed, size: 8)]) { paths in
                for path in paths {
                    precondition(path == self.reviewed || path == self.unreviewed)
                    try FileManager().moveItem(at: path, to: self.trash.appendingPathComponent(path.lastPathComponent))
                    self.state.withLock { $0.trashed.append(path) }
                }
            }
        }, supportsRootCommand: { RootContract.Command(rawValue: $0) != nil })
    }
}

@main
struct CleanWiringTest {
    @MainActor static func main() async throws {
        let manager = FileManager()
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let fake = try WiringFake(root)
        let suite = "clean-wiring-" + UUID().uuidString
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        precondition(CleanCoordinator.features.allSatisfy { !preferences.isOn($0) && !$0.needsIsland })
        var listeners = 0
        var accept = false
        var questions: [(Int, Int64?)] = []
        var suspendQuestion = false
        var questionContinuation: CheckedContinuation<Bool, Never>?
        var optimizeQuestions: [CleanOptimizeTask] = []
        var optimizeAccept = false
        let coordinator = CleanCoordinator(transport: fake.transport, isOn: preferences.isOn,
            listen: { _ in listeners += 1; return { listeners -= 1 } },
            question: { feature, count, bytes in
                precondition(feature == .cleanJunk)
                questions.append((count, bytes))
                if suspendQuestion {
                    return await withCheckedContinuation { questionContinuation = $0 }
                }
                return accept
            },
            optimizeQuestion: { optimizeQuestions.append($0); return optimizeAccept },
            report: { preconditionFailure("Unexpected failure: \($0)") })
        coordinator.scan(.cleanJunk)
        coordinator.apply(.cleanJunk)
        coordinator.optimize(.quickLook)
        await coordinator.waitUntilIdle()
        precondition(fake.state.withLock { $0.scans == 0 } && listeners == 0)
        preferences.set(.cleanJunk, true)
        coordinator.setEnabled(.cleanJunk, true)
        precondition(listeners == 1 && fake.state.withLock { $0.scans == 0 })
        coordinator.scan(.cleanJunk)
        await coordinator.waitUntilIdle()
        coordinator.selection[.cleanJunk] = [fake.reviewed]
        coordinator.apply(.cleanJunk)
        await coordinator.waitUntilIdle()
        precondition(questions.count == 1 && questions[0].0 == 1 && questions[0].1 == 8)
        precondition(manager.fileExists(atPath: fake.reviewed.path))
        let declinedSentinel = try Data(contentsOf: fake.unreviewed)
        precondition(declinedSentinel == Data("sentinel".utf8))
        precondition(fake.state.withLock { $0.trashed.isEmpty })
        accept = true
        coordinator.apply(.cleanJunk)
        await coordinator.waitUntilIdle()
        precondition(fake.state.withLock { $0.trashed == [fake.reviewed] })
        precondition(!manager.fileExists(atPath: fake.reviewed.path))
        let acceptedSentinel = try Data(contentsOf: fake.unreviewed)
        precondition(acceptedSentinel == Data("sentinel".utf8))
        fake.state.withLock { $0.suspended = true }
        coordinator.scan(.cleanJunk)
        for _ in 0..<10_000 {
            if fake.state.withLock({ $0.continuation != nil }) { break }
            await Task.yield()
        }
        let continuation = fake.state.withLock { $0.continuation }
        precondition(continuation != nil, "Fake scan did not start")
        preferences.set(.cleanJunk, false)
        coordinator.setEnabled(.cleanJunk, false)
        precondition(listeners == 0 && coordinator.reviews[.cleanJunk] == nil)
        continuation?.resume()
        await coordinator.waitUntilIdle()
        precondition(coordinator.reviews[.cleanJunk] == nil && !coordinator.busy.contains(.cleanJunk))
        let scans = fake.state.withLock { $0.scans }
        preferences.set(.cleanSystem, true)
        coordinator.setEnabled(.cleanSystem, true)
        precondition(coordinator.rootAvailable)
        coordinator.helperCurrent = false
        precondition(!coordinator.rootAvailable)
        coordinator.scan(.cleanSystem)
        coordinator.apply(.cleanSystem)
        await coordinator.waitUntilIdle()
        precondition(fake.state.withLock { $0.scans == scans })
        precondition(questions.count == 2)
        fake.state.withLock { $0.suspended = false }
        preferences.set(.cleanJunk, true)
        coordinator.setEnabled(.cleanJunk, true)
        coordinator.scan(.cleanJunk)
        await coordinator.waitUntilIdle()
        coordinator.selection[.cleanJunk] = [fake.unreviewed]
        suspendQuestion = true
        coordinator.apply(.cleanJunk)
        for _ in 0..<10_000 {
            if questionContinuation != nil { break }
            await Task.yield()
        }
        precondition(questionContinuation != nil)
        preferences.set(.cleanJunk, false)
        coordinator.setEnabled(.cleanJunk, false)
        questionContinuation?.resume(returning: true)
        await coordinator.waitUntilIdle()
        let staleQuestionSentinel = try Data(contentsOf: fake.unreviewed)
        precondition(staleQuestionSentinel == Data("sentinel".utf8))
        preferences.set(.cleanOptimize, true)
        coordinator.setEnabled(.cleanOptimize, true)
        coordinator.optimize(.quickLook)
        await coordinator.waitUntilIdle()
        precondition(optimizeQuestions == [.quickLook] && questions.count == 3)
        precondition(fake.state.withLock { $0.optimized.isEmpty })
        optimizeAccept = true
        coordinator.optimize(.openWithMenu)
        await coordinator.waitUntilIdle()
        precondition(optimizeQuestions == [.quickLook, .openWithMenu] && questions.count == 3)
        precondition(fake.state.withLock { $0.optimized == [.openWithMenu] })
        precondition(fake.state.withLock { $0.trashed == [fake.reviewed] })
        coordinator.stop()
        precondition(listeners == 0)
        print("PASS: default off; no work on enable; listeners removed; decline preserves sentinels")
        print("PASS: accept trashes reviewed only; stale scan dropped; missing helper verb does nothing")
        print("PASS: stale confirmation dropped; Optimize asks its action question without an item count")
    }
}
