import Foundation

struct TailscaleStatusService: Sendable {
    var executables: [URL]?
    var timeout: Duration = .seconds(2)
    private static let maximumOutput = 256 * 1024

    @concurrent
    func read() async -> TailscaleState {
        let bundled = URL(filePath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
        let candidates = executables ?? [ExecutableLocator.find("tailscale"),
            FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil].compactMap { $0 }
        for executable in candidates {
            guard !Task.isCancelled else { break }
            let request = ProcessRunner.Request(
                executable: executable, arguments: ["status", "--json", "--peers=false"],
                timeout: timeout, outputLimit: Self.maximumOutput)
            guard let output = try? await ProcessRunner.run(request), output.status == 0 else { continue }
            return TailscaleState.parse(output.stdout)
        }
        return .unavailable
    }
}
