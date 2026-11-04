import Foundation

@MainActor
protocol ArchiveDefaultApplicationSetting {
    func setEnabled(_ enabled: Bool, application: URL) async throws
}
