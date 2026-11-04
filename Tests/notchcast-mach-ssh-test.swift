// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/Service/*.swift Tinycast/Platform/ProcessExit.swift
import Foundation

@main struct MachSSHTest {
    static func main() async throws {
        let ssh = MachSSH(address: "remote") { executable, arguments in
            assert(executable == "/usr/bin/ssh")
            assert(arguments == ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                                 "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3", "remote", "uptime"])
            return .init(status: 255, output: "")
        }
        let result = try await ssh.run("uptime")
        assert(result.message == "Unable to reach the remote Mac over SSH")
        for (fixture, expected) in [("hostname 192.0.2.1\n", MachSSH.Route.thunderbolt),
                                    ("user test\nHOSTNAME\tremote.example.ts.net\n", .tailscale)] {
            let connection = MachSSH(address: "remote") { executable, arguments in
                assert(executable == "/usr/bin/ssh" && arguments == ["-G", "remote"])
                return .init(status: 0, output: fixture)
            }
            let route = try await connection.route(thunderboltAddress: "192.0.2.1")
            assert(route == expected)
        }
        assert(MachSSH(address: "-bad", runner: ssh.runner).address == "mbp")
        assert(!MachSSH.isValid("host;echo bad"))
        assert(ssh.terminalScript.contains("exec /bin/zsh -l"))
        assert(ssh.terminalScript.contains("Unable to reach the remote Mac over SSH"))
        assert(ssh.terminalScript.contains("$HOME/chad"))
        print("Mach SSH passed")
    }
}
