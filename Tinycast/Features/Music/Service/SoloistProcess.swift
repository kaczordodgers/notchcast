import Foundation

enum SoloistProcess {
    struct Output: Sendable {
        let status: Int32
        let text: String
    }

    @concurrent
    static func run(_ executable: URL, arguments: [String], timeout: Duration = .seconds(10)) async throws -> Output {
        let name = executable.lastPathComponent
        let request = ProcessRunner.Request(
            executable: executable, arguments: arguments,
            environment: ExecutableLocator.environment(running: executable, adding: ["LC_ALL": "C"], inherited: [:]),
            stderr: .merge,
            timeout: timeout, outputLimit: 1 << 20)
        let output: ProcessRunner.Output
        do { output = try await ProcessRunner.run(request) } catch let failure as ProcessRunner.Failure {
            throw SoloistFailure.process.detail("\(name): \(failure == .timedOut ? "timed out" : "output over 1 MB")")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SoloistFailure.process.detail("\(name): \(SoloistFailure.describe(error))")
        }
        guard let text = String(data: output.stdout, encoding: .utf8) else {
            throw SoloistFailure.process.detail("\(name): output isn’t UTF-8 text")
        }
        return Output(status: output.status, text: text)
    }
}
