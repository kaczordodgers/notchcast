import Foundation

struct AppUpdateBrewRunner: Sendable {
    var arguments = ["outdated", "--cask", "--json=v2"]
    var locate: @Sendable (String) async -> URL? = { await ExecutableLocator.locate($0) }

    @concurrent func outdated() async throws -> Data {
        guard let brew = await locate("brew") else { throw URLError(.resourceUnavailable) }
        let request = ProcessRunner.Request(
            executable: brew, arguments: arguments,
            environment: ExecutableLocator.environment(
                running: brew, adding: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"]),
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
