import AppKit

extension DialogPanel {
    /// Closes the open dialog as Esc would, so its caller gets the cancel option back.
    static func dismissOpen() {
        NSApp.windows.lazy.compactMap { $0 as? DialogPanel }.first { $0.onKey != nil }?.onKey?(.cancel)
    }
}
