import SwiftUI

struct MusicBars: View {
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var start = Date.now

    private static let offsets: [TimeInterval] = [0, -0.35, -0.6, -0.15]
    private static let pulseDuration: TimeInterval = 0.9
    private static let barWidth: CGFloat = 3
    private static let barHeight: CGFloat = 14
    private static let gap: CGFloat = 2
    private static let restingScale = 0.6
    private static let minimumScale = 0.3

    private var animates: Bool { isPlaying && !reduceMotion && isVisible }

    var body: some View {
        TimelineView(.animation(paused: !animates)) { context in
            HStack(spacing: Self.gap) {
                ForEach(Self.offsets.indices, id: \.self) { index in
                    Capsule()
                        .fill(NotchcastTheme.musicForeground)
                        .frame(width: Self.barWidth, height: Self.barHeight)
                        .scaleEffect(y: scale(at: context.date, offset: Self.offsets[index]))
                }
            }
            .frame(height: Self.barHeight)
        }
        .onAppear {
            start = .now
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .accessibilityHidden(true)
    }

    private func scale(at date: Date, offset: TimeInterval) -> Double {
        guard animates else { return Self.restingScale }
        let cycle = (date.timeIntervalSince(start) - offset)
            .truncatingRemainder(dividingBy: Self.pulseDuration * 2) / Self.pulseDuration
        let progress = cycle <= 1 ? cycle : 2 - cycle
        return Self.minimumScale + (1 - Self.minimumScale) * UnitCurve.easeInOut.value(at: progress)
    }
}
