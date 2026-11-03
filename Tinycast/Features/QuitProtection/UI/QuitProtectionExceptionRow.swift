import SwiftUI

struct QuitProtectionExceptionRow: View {
    let identifier: String
    let remove: () -> Void

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) }
    private var name: String {
        url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? identifier
    }

    var body: some View {
        LabeledContent {
            BarButton(isCompact: true, action: remove) {
                SymbolImage(name: "xmark", size: Theme.Size.menuIcon).accessibilityHidden(true)
            }
                .accessibilityLabel(Text("Remove \(name)"))
        } label: {
            Label {
                Text(name)
            } icon: {
                if let url {
                    Image(nsImage: IconCache.icon(forFile: url.path))
                        .resizable()
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
