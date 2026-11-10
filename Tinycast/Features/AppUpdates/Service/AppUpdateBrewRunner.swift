import Foundation

struct AppUpdateBrewRunner: Sendable {
    var path = "/opt/homebrew/bin/brew"
    var arguments = ["outdated", "--cask", "--json=v2"]

    @concurrent func outdated() async throws -> Data {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw URLError(.resourceUnavailable)
        }
        let request = ProcessRunner.Request(
            executable: URL(filePath: path), arguments: arguments,
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1",
                          "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            timeout: .seconds(30), outputLimit: AppUpdateFeed.limit)
        let output: ProcessRunner.Output
        do { output = try await ProcessRunner.run(request) } catch ProcessRunner.Failure.timedOut {
            throw URLError(.timedOut)
        } catch ProcessRunner.Failure.outputLimit {
            throw URLError(.dataLengthExceedsMaximum)
        }
        guard output.status == 0 else { throw URLError(.cannotLoadFromNetwork) }
        return output.stdout
    }
}
