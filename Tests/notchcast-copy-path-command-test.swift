// notchcast-kit: host command
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/CopyPath/Model/*.swift Tinycast/Features/CopyPath/Service/*.swift Tinycast/Features/CopyPath/CopyPathModule*.swift
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

enum DialogTone { case neutral }
enum NotchcastFeature { case copyPath }
@MainActor final class AppCore {}
@main struct CopyTests {
    @MainActor static func main() async {
        let module = CopyPathModule(makeService: { CopyPathService { request in
            precondition(request == .finderSelection)
            return ["/test/file"]
        } })
        module.start()
        var copied = ""
        var reported = ""
        module.copyFromLauncher(target: CopyPathTarget(processID: 1, bundleID: "com.apple.finder"),
                                home: "/test", copy: { copied = $0; return true }, report: { reported = $0 })
        await module.commandTask?.value
        precondition(copied == "~/file" && reported == "Copied path")
        module.stop()
        struct Unknown: Error {}
        let causes: [(any Error, String)] = [
            (CopyPathService.Failure.needsAutomation, "Allow Automation access to copy the path."),
            (CopyPathService.Failure.needsAccessibility, "Allow Accessibility access to copy the path."),
            (CopyPathService.Failure.timedOut, "The app did not respond in time."),
            (CopyPathService.Failure.unreadable, "Could not read the path."),
            (Unknown(), "Could not read the path."),
        ]
        for (failure, message) in causes {
            let failing = CopyPathModule(makeService: { CopyPathService { _ in throw failure } })
            failing.start()
            failing.copyFromLauncher(target: CopyPathTarget(processID: 1, bundleID: "com.apple.finder"),
                                     home: "/test", copy: { _ in true }, report: { reported = $0 })
            await failing.commandTask?.value
            precondition(reported == message, "\(failure) reported \(reported)")
            failing.stop()
        }
        let (gate, release) = AsyncStream<Void>.makeStream()
        let pending = CopyPathModule(makeService: { CopyPathService { _ in
            for await _ in gate { break }
            return ["/test/late"]
        } })
        pending.start()
        var lateCopied = false
        pending.copyFromLauncher(target: CopyPathTarget(processID: 1, bundleID: "com.apple.finder"),
                                 home: "/test", copy: { _ in lateCopied = true; return true }, report: { _ in lateCopied = true })
        let task = pending.commandTask
        pending.stop()
        release.yield()
        await task?.value
        precondition(!lateCopied)
        let entries = CopyPathModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.copyPath] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === CopyPathModule.shared)
        print("Verified launcher action resolves with fake reader, copies result and reports success; a stopped module copies nothing")
        print("Verified each read failure reports its own message")
    }
}
