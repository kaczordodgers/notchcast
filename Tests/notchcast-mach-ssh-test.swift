// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Features/MachRemote/Service/*.swift
import Foundation

// Runs only what follows the ssh call, under macOS's default shell, where `status` is read-only.
func runFailureTail(of script: String) throws -> (status: Int32, output: String) {
    let start = script.range(of: "; rc=$?")!
    let tail = "(exit 255)" + script[start.lowerBound...].replacingOccurrences(of: "exec /bin/zsh -l", with: "exit 7")
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", tail]
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return (process.terminationStatus, output)
}

@main struct MachSSHTest {
    static func main() async throws {
        let ssh = MachSSH(address: "remote") { executable, arguments in
            assert(executable == "/usr/bin/ssh")
            assert(arguments == ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                                 "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3", "remote", "uptime"])
            return .init(status: 255, output: "")
        }
        let result = try await ssh.run("uptime")
        assert(result.status == 255)
        for address in ["", "-bad", "host;echo bad"] {
            do {
                _ = try await MachSSH(address: address, runner: ssh.runner).run("uptime")
                assertionFailure("Invalid address ran")
            } catch MachSSH.ConfigurationError.address {}
        }
        assert(MachSSH.isValid("user@2001:db8::1"))
        let script = try ssh.terminalScript(directory: "/workspace")
        do {
            _ = try ssh.terminalScript(directory: "")
            assertionFailure("Missing directory accepted")
        } catch MachSSH.ConfigurationError.path {}
        assert(!MachSSH.isValid("host;echo bad"))
        assert(script.contains("exec /bin/zsh -l"))
        assert(script.contains("Unable to reach the remote Mac over SSH"))
        assert(script.contains("/workspace"))
        let tail = try runFailureTail(of: script)
        precondition(tail.status == 7 && tail.output.contains("Unable to reach"))
        let homeScript = try ssh.terminalScript(directory: "~/code")
        precondition(homeScript.contains("$HOME/"))
        precondition(MachSSH.remotePath("/opt/up date") == "'/opt/up date'")
        precondition(MachSSH.remotePath("~/bin/up'd") == #""$HOME/"'bin/up'\''d'"#)
        print("Mach SSH passed")
    }
}
