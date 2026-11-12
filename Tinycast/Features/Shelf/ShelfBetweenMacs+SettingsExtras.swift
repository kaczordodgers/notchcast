import SwiftUI

extension NotchcastFeatureSettingsExtras {
    static var shelfBetweenMacs: Self { Self(enabledRows: AnyView(ShelfReceivedSection())) }
}
