// notchcast-sources: Tinycast/Features/Tweaks/Service/TweakProfileRunner.swift
import Foundation

@main
struct TweakProfileRunnerTests {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = Data("fixture".utf8)
        let runner = TweakProfileRunner { file in
            precondition(file.pathExtension == "mobileconfig")
            let contents = try Data(contentsOf: file)
            precondition(contents == Data("fixture".utf8))
        }
        let file = try await runner.requestApproval(data: data, folder: folder)
        let contents = try Data(contentsOf: file)
        precondition(contents == data)
        enum Failure: Error { case refused }
        let failing = TweakProfileRunner { _ in throw Failure.refused }
        do {
            _ = try await failing.requestApproval(data: data, folder: folder)
            preconditionFailure("Expected failure")
        } catch Failure.refused {}
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(files.count == 1)
        print("Profile runner: staged file, injected approval handoff and failure cleanup passed")
    }
}
