// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsIslandBridge.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsQueueController.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivityCenter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandMessage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandValue.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation

@main
@MainActor
struct DownloadsIslandTest {
    private struct HeldRunner: DownloadRunner {
        let kind = "hold"
        let tools: [DownloadTool] = []

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            await context.report(DownloadProgress(fraction: 0.5, stage: nil))
            try await Task.sleep(for: .seconds(60))
            return nil
        }
    }

    static func main() async throws {
        testActivity()
        testFailures()
        try await testBridge()
        print("nc-Downloads-island-test: passed activity, batch counts, failures once and the live bridge")
    }

    private static func job(_ id: String, _ state: DownloadState, fraction: Double? = nil, detail: String? = nil,
                            age: TimeInterval = 0) -> DownloadJob {
        var job = DownloadJob(id: id, kind: "video", source: "https://example.com/\(id)", title: "Title \(id)",
                              created: Date(timeIntervalSince1970: 1000 + age))
        job.state = state
        job.detail = detail
        job.progress = fraction.map { DownloadProgress(fraction: $0, stage: nil) }
        return job
    }

    private static func testActivity() {
        var policy = DownloadsIslandPolicy(loaded: [])
        precondition(policy.update([]).shown == nil, "Idle shows nothing")
        precondition(policy.update([job("old", .done)]).shown == nil, "Only finished jobs is idle")
        let waiting = policy.update([job("a", .waiting), job("b", .waiting)]).shown
        precondition(waiting == .init(title: nil, value: .count(0, of: 2), progress: nil), "\(String(describing: waiting))")
        let running = policy.update([job("a", .running, fraction: 0.4), job("b", .waiting, age: 1)]).shown
        precondition(running == .init(title: "Title a", value: .count(0, of: 2), progress: 0.4))
        let unknown = policy.update([job("a", .running), job("b", .waiting, age: 1)]).shown
        precondition(unknown?.progress == nil && unknown?.title == "Title a")
        let half = policy.update([job("a", .done), job("b", .running, fraction: 0.1, age: 1)]).shown
        precondition(half == .init(title: "Title b", value: .count(1, of: 2), progress: 0.1))
        let grown = policy.update([job("a", .done), job("b", .failed, age: 1), job("c", .waiting, age: 2)]).shown
        precondition(grown?.value == .count(2, of: 3), "A job added mid-batch joins it")
        precondition(policy.update([job("a", .done), job("b", .failed), job("c", .done)]).shown == nil)
        let next = policy.update([job("a", .done), job("d", .waiting)]).shown
        precondition(next?.value == .count(0, of: 1), "An idle queue starts a new batch")
    }

    private static func testFailures() {
        var policy = DownloadsIslandPolicy(loaded: [job("old", .failed, detail: "Old"), job("b", .waiting)])
        precondition(policy.update([job("old", .failed, detail: "Old"), job("b", .running)]).failures.isEmpty,
                     "Failures already in the loaded queue are never announced")
        let failed = policy.update([job("old", .failed), job("b", .failed, detail: "No network")]).failures
        precondition(failed.map(\.id) == ["b"])
        precondition(policy.update([job("old", .failed), job("b", .failed)]).failures.isEmpty, "Once per job")
        precondition(DownloadsIslandPolicy.message(for: failed[0]) == "Title b: No network")
        let long = job(String(repeating: "x", count: 60), .failed, detail: "Gone")
        let text = DownloadsIslandPolicy.message(for: long)
        precondition(text.hasSuffix("…: Gone") && text.count == 40 + 6, text)
        precondition(DownloadsIslandPolicy.message(for: job("c", .failed)) == "Title c")
    }

    private static func testBridge() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-island-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "downloads.json")
        let center = IslandActivityCenter(sleep: { _ in try? await Task.sleep(for: .seconds(600)) })
        var controller: DownloadsQueueController? = makeController(file: file, root: root)
        DownloadsIslandBridge.track(controller!, center: center)
        controller!.start { $0.register(HeldRunner()) }
        await controller!.settle()
        let queue = controller!.queue!
        queue.enqueue(kind: "hold", sources: ["https://example.com/held"])
        try await eventually { center.activities.first?.progress == 0.5 }
        let shown = center.activities[0]
        precondition(center.activities.count == 1 && shown.kind == .transfer && shown.value == .count(0, of: 1))
        queue.enqueue(kind: "missing", sources: ["https://example.com/broken"])
        try await eventually { center.message != nil }
        precondition(center.message?.tone == .danger && center.message?.text.hasPrefix("https://example.com/broken: ") == true)
        queue.cancel(queue.jobs[0].id)
        try await eventually { center.activities.isEmpty }
        controller!.stop()
        await controller!.settle()
        controller = nil

        let fresh = IslandActivityCenter(sleep: { _ in try? await Task.sleep(for: .seconds(600)) })
        let relaunched = makeController(file: file, root: root)
        DownloadsIslandBridge.track(relaunched, center: fresh)
        relaunched.start { $0.register(HeldRunner()) }
        await relaunched.settle()
        precondition(relaunched.queue?.jobs.contains { $0.state == .failed } == true)
        await drain()
        precondition(fresh.message == nil && fresh.activities.isEmpty, "Relaunch repeats no failure")
        relaunched.queue!.enqueue(kind: "hold", sources: ["https://example.com/again"])
        try await eventually { !fresh.activities.isEmpty }
        relaunched.stop()
        try await eventually { fresh.activities.isEmpty }
        await relaunched.settle()
    }

    private static func makeController(file: URL, root: URL) -> DownloadsQueueController {
        DownloadsQueueController(file: file, destination: root.appending(path: "out"),
                                 tools: DownloadToolLookup(directories: [], home: root),
                                 report: { preconditionFailure($0) })
    }

    private static func drain() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private static func eventually(file: StaticString = #file, line: UInt = #line,
                                   _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out", file: file, line: line)
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
