// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/RemoteScreenAddress.swift
import Foundation

enum ProcessRunner {
    struct Request { let executable: URL; let arguments: [String]; let timeout: Duration }
    struct Result { let status: Int32 }
    enum Failure: Error { case timedOut }
    static func run(_ request: Request) async throws -> Result {
        precondition(request.executable.path == "/bin/launchctl")
        precondition(request.arguments == ["print", "system/com.apple.screensharing"])
        throw Failure.timedOut
    }
}

@main struct ScreenTimeoutTest {
    static func main() async throws {
        do {
            _ = try await RemoteScreenAddress.current()
            fatalError("Timeout reported as sharing disabled")
        } catch ProcessRunner.Failure.timedOut {}
        print("PASS launchctl timeout remains an error rather than sharing disabled")
    }
}
