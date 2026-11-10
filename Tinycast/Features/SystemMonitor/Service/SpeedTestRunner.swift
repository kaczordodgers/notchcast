import Foundation

nonisolated struct SpeedTestRunner: Sendable {
    @concurrent
    func run(_ phase: SpeedTestPhase) async throws -> SpeedTestResult.Measurement {
        let request = ProcessRunner.Request(
            executable: URL(fileURLWithPath: "/usr/bin/networkQuality"),
            arguments: ["-c", "-M", "30", phase == .download ? "-u" : "-d"])
        let output = try await ProcessRunner.run(request)
        guard output.status == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        return try SpeedTestResult.parse(output.stdout, phase: phase)
    }
}
