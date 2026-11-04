// notchcast-sources: -parse-as-library notchcast/root/RootCaller.swift
// notchcast-sources: notchcast/root/CallerRequirement.swift notchcast/root/RootContract.swift
import Darwin

@main
struct RootCallerTest {
    static func main() {
        precondition(geteuid() != 0)
        for command in RootContract.Command.allCases {
            var checks = 0
            let publicRead = command == .version || command == .ping
            precondition(RootCaller.permits(command) { checks += 1; return false } == publicRead)
            precondition(checks == (publicRead ? 0 : 1))
            precondition(RootCaller.permits(command) { true })
        }
        precondition(!RootCaller.authorized())
        precondition(RootContract.unauthorizedCallerExit == 78)
        print("PASS: unauthorized identities refused, authorized identity accepted, public probes exempt")
    }
}
