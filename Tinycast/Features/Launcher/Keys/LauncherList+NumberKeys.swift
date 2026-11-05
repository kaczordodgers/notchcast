import SwiftUI

extension LauncherList {
    func numberSlot(for app: AppEntry) -> Character? {
        guard let index = results.firstIndex(where: { $0.id == app.id }) else { return nil }
        return LauncherNumberKeys.badgeSlot(
            entryIndex: index, query: numberKeyPalette.query,
            enabled: NotchcastPreferences.shared.isOn(.launcherNumberKeys))
    }
}
