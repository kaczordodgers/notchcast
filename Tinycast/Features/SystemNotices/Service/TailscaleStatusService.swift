import Foundation

struct TailscaleStatusService: Sendable {
    var executable: URL?
    var timeout: Duration = .seconds(2)
    private static let maximumOutput = 256 * 1024

    @concurrent
    func read() async -> TailscaleState {
        let bundled = URL(filePath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
        let executable = executable ?? ExecutableLocator.find("tailscale")
            ?? (FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil)
        guard let executable, !Task.isCancelled else { return .unavailable }
        let request = ProcessRunner.Request(
            executable: executable, arguments: ["status", "--json", "--peers=false"],
            timeout: timeout, outputLimit: Self.maximumOutput)
        guard let output = try? await ProcessRunner.run(request), output.status == 0 else { return .unavailable }
        return TailscaleState.parse(output.stdout)
    }
}
