import AppKit

@MainActor
final class ArchiveServices: NSObject {
    @objc func compress(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        submit(pasteboard, format: .zip)
    }

    @objc func compressSmall(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        submit(pasteboard, format: .small)
    }

    @objc func compressFast(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        submit(pasteboard, format: .fast)
    }

    private func submit(_ pasteboard: NSPasteboard, format: ArchiveCompression) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        ArchiveCompressionCommands.submit(urls, format: format)
    }
}
