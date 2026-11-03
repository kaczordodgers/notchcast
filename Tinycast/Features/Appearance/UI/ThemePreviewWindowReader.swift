import SwiftUI

struct ThemePreviewWindowReader: NSViewRepresentable {
    @MainActor final class Host {
        weak var window: NSWindow?
    }

    let host: Host

    func makeNSView(context: Context) -> NSView { Reader(host: host) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Reader: NSView {
        let host: Host

        init(host: Host) {
            self.host = host
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host.window = window
        }
    }
}
