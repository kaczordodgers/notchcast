import SwiftUI

extension NotchcastFeatureSettingsExtras {
    static var cleaningMode: Self {
        Self(detail: String(localized: "Media keys still work.", table: "Notchcast"),
             label: AnyView(CleaningModeRemainingLabel()))
    }
}

private struct CleaningModeRemainingLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if NotchcastCore.cleaning.remaining > 0 {
                Text("\(Duration.seconds(NotchcastCore.cleaning.remaining).formatted(.units())) left")
            }
        }
    }
}
