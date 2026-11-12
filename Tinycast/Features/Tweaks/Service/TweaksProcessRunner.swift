import Foundation

nonisolated struct TweaksProcessRunner: Sendable {
    enum Failure: Error { case invalidExecutable, timedOut, failed(Int32) }
    static let allowedExecutables: Set<String> = [
        "/usr/bin/defaults", "/usr/bin/open", "/usr/bin/killall", "/bin/chflags"
    ]

    func run(_ executable: String, arguments: [String], timeout: TimeInterval = 5) throws -> String {
        guard Self.allowedExecutables.contains(executable) else { throw Failure.invalidExecutable }
        do {
            let output = try ProcessRunner.runBlocking(.init(
                executable: URL(filePath: executable), arguments: arguments, environment: [:],
                timeout: .seconds(timeout)))
            guard output.status == 0 else { throw Failure.failed(output.status) }
            guard let text = String(data: output.stdout, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return text
        } catch ProcessRunner.Failure.timedOut {
            throw Failure.timedOut
        }
    }
}
