import SwiftUI

/// Orion's level beside a song (ported from Damian's Orion, `MusicParts.swift` `LevelBars`): four bars that sway
/// while a track plays. Paused, Reduce Motion or Show animations off leave them still at their resting level. It is
/// a sign, not a meter: nothing here reads the audio. `level` draws a still input level instead (Listening).
struct IslandOrionBars: View {
    let moving: Bool
    var level: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var high = false

    private typealias Bars = NotchcastTheme.Visualizer.Orion

    private var animates: Bool { moving && level == nil && !reduceMotion && Motion.isEnabled }

    var body: some View {
        HStack(spacing: Bars.gap) {
            ForEach(0..<Bars.count, id: \.self) { index in
                Capsule()
                    .fill(NotchcastTheme.Colors.primary)
                    .frame(width: Bars.width, height: NotchcastTheme.Visualizer.height)
                    .scaleEffect(y: scale(index), anchor: .center)
                    .animation(animates ? .easeInOut(duration: Bars.cycle).repeatForever(autoreverses: true)
                        .delay(Bars.offsets[index]) : nil, value: high)
            }
        }
        .frame(height: NotchcastTheme.Visualizer.height)
        .onAppear { high = true }
        .accessibilityHidden(true)
    }

    /// Playing without motion holds one frame of the sway, each bar at its own offset into the cycle, so a playing
    /// song still reads apart from a paused one at rest.
    private func scale(_ index: Int) -> CGFloat {
        if let level { return max(Bars.lowestLevel, level) }
        if animates { return high ? 1 : Bars.lowestLevel }
        guard moving else { return Bars.restingLevel }
        let sway = abs(cos(.pi * Bars.offsets[index] / Bars.cycle))
        return Bars.lowestLevel + (1 - Bars.lowestLevel) * sway
    }
}
