// notchcast-addon-order: 20
// notchcast-readme: Keyboard & Mouse: Show Desktop with F3
import Foundation

enum ShowDesktopAddon: NotchcastAddon {
    static let switchID = "showDesktop"

    static let switches = [
        NotchcastSwitch(
            id: "showDesktop",
            title: String(localized: "Show Desktop with F3", table: "NotchcastShowDesktop"),
            subtitle: String(localized: "Press again to restore windows.", table: "NotchcastShowDesktop"),
            category: .keyboardMouse,
            defaultEnabled: true,
            requiredGrants: [.accessibility]
        ),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ShowDesktopModule(context: context, system: .live)
    }
}
