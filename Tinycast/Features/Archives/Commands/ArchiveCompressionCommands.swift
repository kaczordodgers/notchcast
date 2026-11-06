import AppKit

@MainActor
enum ArchiveCompressionCommands {
    static var selection: () async throws -> [URL] = { [] }
    nonisolated static let standard = NotchcastCommand(slug: "compress", name: String(localized: "Compress with Notchcast", table: "Notchcast"), sfSymbol: "archivebox", feature: .archives, isEnabled: { ArchiveCommands.enabled }, run: { run(.zip) })
    nonisolated static let small = NotchcastCommand(slug: "compress-small", name: String(localized: "Compress Small", table: "Notchcast"), sfSymbol: "archivebox", feature: .archives, isEnabled: { ArchiveCommands.enabled }, run: { run(.small) })
    nonisolated static let fast = NotchcastCommand(slug: "compress-fast", name: String(localized: "Compress Fast", table: "Notchcast"), sfSymbol: "archivebox", feature: .archives, isEnabled: { ArchiveCommands.enabled }, run: { run(.fast) })

    static func run(_ format: ArchiveCompression) {
        guard ArchiveCommands.enabled, NotchcastCore.archives.isRunning else {
            submit([], format: format)
            return
        }
        Task {
            do {
                let urls = try await selection()
                submit(urls, format: format)
            } catch {
                AppCore.shared.showMessage(String(localized: "Couldn’t read the Finder selection.", table: "Notchcast"), tone: .danger)
            }
        }
    }

    static func submit(_ urls: [URL], format: ArchiveCompression) {
        guard ArchiveCommands.enabled, NotchcastCore.archives.isRunning else {
            AppCore.shared.showMessage(String(localized: "The archive engine is not running.", table: "Notchcast"), tone: .danger)
            return
        }
        guard !urls.isEmpty else {
            AppCore.shared.showMessage(String(localized: "No files selected in Finder.", table: "Notchcast"), tone: .danger)
            return
        }
        NotchcastCore.archives.queue.compress(urls, format: format)
    }
}
