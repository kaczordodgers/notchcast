import Foundation
import Darwin

struct AppUpdateBrewRunner: Sendable {
    var path = "/opt/homebrew/bin/brew"
    var arguments = ["outdated", "--cask", "--json=v2"]

    @concurrent func outdated() async throws -> Data {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw URLError(.resourceUnavailable)
        }
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        process.environment = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1",
                               "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let exit = try process.runObservingExit()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            exit.wait()
        }
        defer { pipe.fileHandleForReading.closeFile() }
        return try await withTaskCancellationHandler {
            let deadline = ContinuousClock.now + .seconds(30)
            var data = Data()
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
            while true {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 { data.append(contentsOf: buffer.prefix(count)) }
                guard data.count <= AppUpdateFeed.limit else { throw URLError(.dataLengthExceedsMaximum) }
                if count == 0, !process.isRunning { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            exit.wait()
            guard process.terminationStatus == 0 else { throw URLError(.cannotLoadFromNetwork) }
            return data
        } onCancel: {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
