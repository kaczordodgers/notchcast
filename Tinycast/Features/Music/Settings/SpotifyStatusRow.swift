import SwiftUI

struct SpotifyStatusRow: View {
    let module: SpotifyConnectModule

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.xs) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    SymbolImage(name: symbol, size: Theme.Typography.menuSymbolSize).accessibilityHidden(true)
                }
                Text(title)
                if case .failed = module.speaker.state {
                    // ai-design-check-ignore-next-line sentence-case -- Exact design-brief copy.
                    Button("Try Again") {
                        module.speaker.setEnabled(false)
                        module.speaker.setEnabled(module.isEnabled)
                    }
                }
            }
            .foregroundStyle(tint)
        } label: {
            Text("Status")
            if let subtitle { Text(subtitle) }
        }
    }

    private var busy: Bool {
        switch module.speaker.state {
        case .starting, .downloading: true
        default: false
        }
    }

    private var title: String {
        switch module.speaker.state {
        case .off, .failed: String(localized: "Stopped")
        case .starting: String(localized: "Starting…")
        case .running: String(localized: "Ready as “\(module.deviceName)”", table: "Notchcast")
        case .noKey: String(localized: "Needs an API key", table: "Notchcast")
        case .needsBuild: String(localized: "Needs Soloist", table: "Notchcast")
        case .downloading: String(localized: "Downloading Soloist…", table: "Notchcast")
        case .waitingForOther: String(localized: "Waiting for another Soloist", table: "Notchcast")
        case .expiresSoon(let days): String(localized: "Expires in \(days) days", table: "Notchcast")
        }
    }

    private var subtitle: String? {
        switch module.speaker.state {
        case .waitingForOther: String(localized: "Another app is running Soloist with this key. Notchcast starts when it quits.", table: "Notchcast")
        case .expiresSoon: String(localized: "Download Soloist again to keep playing.", table: "Notchcast")
        case .failed(let reason): reason.message
        default: nil
        }
    }

    private var tint: Color {
        switch module.speaker.state {
        case .running: Theme.Colors.success
        case .failed: Theme.Colors.destructive
        case .noKey, .needsBuild, .waitingForOther, .expiresSoon: Theme.Colors.warning
        default: Theme.Colors.textSecondary
        }
    }

    private var symbol: String {
        switch module.speaker.state {
        case .running: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        default: "exclamationmark.triangle.fill"
        }
    }
}
