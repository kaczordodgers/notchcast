import SwiftUI

struct BrightnessDisplayRow: View {
    private static let sliderWidth: CGFloat = 160
    let display: BrightnessDisplay
    let controller: BrightnessController
    @State private var value: Double?
    @State private var write: Task<Void, Never>?
    @State private var failed = false

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Slider(value: Binding(get: { value ?? display.level.value }, set: setLevel),
                       in: (display.level.softwareOnly ? 0 : -BrightnessLevel.extraDimmingRange)...1)
                    .frame(width: Self.sliderWidth)
                    .accessibilityLabel(Text("Brightness of \(display.name)"))
                    .accessibilityValue(Text((value ?? display.level.value) < 0 ? String(localized: "Dim")
                        : max(value ?? display.level.value, 0).formatted(.percent.precision(.fractionLength(0)))))
                Text((value ?? display.level.value) < 0 ? String(localized: "Dim")
                     : max(value ?? display.level.value, 0).formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
            }
        } label: {
            Label {
                Text(display.name)
                Text(failed ? String(localized: "Not responding") : controlTitle)
                    .foregroundStyle(failed ? Theme.Colors.warning : Theme.Colors.textSecondary)
            } icon: {
                SymbolImage(name: display.isBuiltIn ? "laptopcomputer" : "display", size: Theme.Size.menuIcon)
                    .accessibilityHidden(true)
            }
        }
        .onDisappear { write?.cancel() }
        .onChange(of: display.level) { _, _ in failed = false }
    }

    private var controlTitle: String {
        switch display.control {
        case .system: String(localized: "Built-in")
        case .ddc: "DDC"
        case .software: String(localized: "Software dimming")
        }
    }

    private func setLevel(_ level: Double) {
        value = level
        write?.cancel()
        write = Task {
            let result = await controller.set(level, for: display.id)
            guard !Task.isCancelled else { return }
            failed = result == nil
            value = nil
        }
    }
}
