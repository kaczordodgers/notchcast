import AppKit

@MainActor
enum ArchiveCompressionCommands {
    nonisolated static let standard = NotchcastCommand(slug: "compress", name: String(localized: "Compress with Notchcast", table: "Notchcast"), sfSymbol: "archivebox", feature: .archives, isEnabled: { ArchiveCommands.enabled }, run: { run(.zip) })
    nonisolated static let small = NotchcastCommand(slug: "compress-small", name: String(localized: "Compress Small", table: "Notchcast"), sfSymbol: "archivebox", feature: .archives, isEnabled: { ArchiveCommands.enabled }, run: { run(.small) })
    nonisolated static let fast = NotchcastCommand(slug: "compress-fast", name: String(localized: "Compress Fast", table: "Notchcast"), sfSymbol: "archivebox", feature: .archives, isEnabled: { ArchiveCommands.enabled }, run: { run(.fast) })

    static func run(_ format: ArchiveCompression) {
        guard ArchiveCommands.enabled, ArchiveModule.shared.isRunning else {
            submit([], format: format)
            return
        }
        Task {
            do {
                let urls = try await NotchcastHost.current.finderSelection().map { URL(filePath: $0) }
                submit(urls, format: format)
            } catch {
                NotchcastHost.current.showMessage(String(localized: "Couldn’t read the Finder selection.", table: "Notchcast"), .danger)
            }
        }
    }

    static func submit(_ urls: [URL], format: ArchiveCompression) {
        guard ArchiveCommands.enabled, ArchiveModule.shared.isRunning else {
            NotchcastHost.current.showMessage(String(localized: "The archive engine is not running.", table: "Notchcast"), .danger)
            return
        }
        guard !urls.isEmpty else {
            NotchcastHost.current.showMessage(String(localized: "No files selected in Finder.", table: "Notchcast"), .danger)
            return
        }
        ArchiveModule.shared.queue.compress(urls, format: format)
    }
}
