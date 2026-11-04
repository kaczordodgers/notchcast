import SwiftUI

struct QuitProtectionExceptionRow: View {
    let identifier: String
    let remove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        let name = url.map { QuitProtectionAppName.displayName(FileManager.default.displayName(atPath: $0.path)) }
            ?? identifier
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
