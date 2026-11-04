// notchcast-sources: Tinycast/Features/CaptureTrimmer/Service/CaptureTrimmerModule*.swift
// notchcast-sources: Tinycast/Features/CaptureTrimmer/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift

import Foundation

enum CaptureTrimService {
    enum Failure: LocalizedError {
        case cannotWrite
        var errorDescription: String? { "Fake export failed" }
    }
    @MainActor static var saves = 0
    @MainActor static var fails = false
    static func recoverable(in folder: URL) async throws -> [URL] { [folder] }
    @MainActor static func save(source: URL, trim: CaptureTrim, destination: URL) async throws -> URL {
        saves += 1
        if fails { throw Failure.cannotWrite }
        return destination
    }
}

@main
struct CaptureTrimmerModuleTest {
    @MainActor static func main() async throws {
        let suite = "trimmer-module-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var copied: URL?
        let module = CaptureTrimmerModule(workFolder: folder) { copied = $0 }
        let controller = NotchcastModuleController([
            .init(requires: [.captureTrimmer], module: module)], preferences: preferences)
        preferences.set(.captureTrimmer, true)
        controller.run()
        precondition(module.enabled)
        for _ in 0..<1000 where module.recoverable.isEmpty { await Task.yield() }
        precondition(module.recoverable == [folder])
        let trim = CaptureTrim(duration: 1, framesPerSecond: 30)
        _ = try await module.save(source: folder, trim: trim, destination: folder, copy: true)
        precondition(CaptureTrimService.saves == 1 && copied == folder)
        CaptureTrimService.fails = true
        do {
            _ = try await module.save(source: folder, trim: trim, destination: folder)
            preconditionFailure("export must fail")
        } catch { precondition(error.localizedDescription == "Fake export failed") }
        preferences.set(.captureTrimmer, false)
        for _ in 0..<1000 where module.enabled { await Task.yield() }
        precondition(!module.enabled && module.recoverable.isEmpty)
        do {
            _ = try await module.save(source: folder, trim: trim, destination: folder)
            preconditionFailure("disabled export")
        } catch is CancellationError {}
        precondition(CaptureTrimService.saves == 2)
        print("PASS: module switch, recovery, export, clipboard and failure")
    }
}
