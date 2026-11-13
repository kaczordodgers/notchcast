// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/JobOutput.swift
// notchcast-kit: platform
import Foundation

@main
struct ArchivesDefaultsTest {
    @MainActor static func main() async throws {
        let application = URL(fileURLWithPath: "/Applications/Fixture.app")
        let types = Array(ArchiveFormat.typeIdentifiers.prefix(4))
        var attempted: [String] = []
        try await ArchiveDefaultApplicationService.apply(
            enabled: true, application: application, supported: Set(ArchiveFormat.typeIdentifiers), current: { _ in nil }
        ) { attempted.append($0) }
        expect(attempted == ArchiveFormat.defaultTypeIdentifiers, "claims only eligible archive types")
        expect(!attempted.contains("public.iso-image"), "ISO never claimed by real default-service path")
        expect(!attempted.contains("com.apple.installer-package-archive"), "PKG never claimed by real default-service path")
        attempted = []
        do {
            try await ArchiveDefaultApplicationService.apply(
                enabled: false, application: application, supported: Set(types.prefix(3)),
                current: { $0 == types[2] ? URL(fileURLWithPath: "/Applications/Other.app") : application }
            ) { identifier in
                attempted.append(identifier)
                throw ArchiveFailure.filesystem("failure-\(identifier)")
            }
            fatalError("restore errors lost")
        } catch {
            expect(attempted == Array(types.prefix(2)), "restore filters unsupported and other-app types")
            let message = String(describing: error)
            expect(attempted.allSatisfy { message.contains("failure-\($0)") }, "restore collects each type error")
        }
        print("PASS: fake default application service filters restore types and collects per-type errors")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
}
