// notchcast-sources: Tinycast/Features/MachRemote/Integration/MachRemoteModule+Actions.swift
// notchcast-kit: host
import AppKit

enum DialogTone {}

@MainActor final class MachRemoteModule {
    var automation: Task<Void, Never>?
}

@MainActor struct NotchcastPreferences {
    static let shared = Self()
    func isOn(_ feature: Feature) -> Bool { true }
    enum Feature { case machRemote, sendFiles }
}

@MainActor struct UpdateRemoteModule {
    static let shared = Self()
    func update() {}
}

@MainActor final class SendFilesModule {
    static let shared = SendFilesModule()
    var sent: [URL] = []
    func send(_ urls: [URL]) { sent = urls }
}

@MainActor enum MachSSHProcessRunner {
    static var output = ""
    static var script = ""
    struct Result { let status: Int; let output: String }
    static func run(_ executable: String, _ arguments: [String]) async throws -> Result {
        script = arguments.last ?? ""
        return Result(status: 0, output: output)
    }
}

@main @MainActor struct FinderPathsTest {
    static func main() async {
        let module = MachRemoteModule()
        MachSSHProcessRunner.output = "/tmp/one\nname\0/tmp/second\0\n"
        module.sendFinderSelection()
        await module.automation?.value
        precondition(SendFilesModule.shared.sent.map(\.path) == ["/tmp/one\nname", "/tmp/second"],
                     "Finder filenames must preserve newlines")
        precondition(MachSSHProcessRunner.script.contains("character id 0"))
        SendFilesModule.shared.sent = []
        MachSSHProcessRunner.output = "relative\0\n"
        module.sendFinderSelection()
        await module.automation?.value
        precondition(SendFilesModule.shared.sent.isEmpty, "Relative paths must be refused")
        print("PASS Finder newline filenames and relative-path refusal")
    }
}
