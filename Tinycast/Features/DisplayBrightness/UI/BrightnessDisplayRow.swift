import SwiftUI

struct BrightnessDisplayRow: View {
    private static let sliderWidth: CGFloat = 160
    let display: BrightnessDisplay
    @State private var state: BrightnessDisplayRowState

    init(display: BrightnessDisplay, controller: BrightnessController) {
        self.display = display
        _state = State(initialValue: BrightnessDisplayRowState(display: display, controller: controller))
    }

    var body: some View {
        @Bindable var state = state
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Slider(value: $state.value,
                       in: (display.level.softwareOnly ? 0 : -BrightnessLevel.extraDimmingRange)...1)
                    .frame(width: Self.sliderWidth)
                    .accessibilityLabel(Text("Brightness of \(display.name)", tableName: "Notchcast"))
                    .accessibilityValue(Text(state.value < 0 ? String(localized: "Dim", table: "Notchcast")
                        : max(state.value, 0).formatted(.percent.precision(.fractionLength(0)))))
                Text(state.value < 0 ? String(localized: "Dim", table: "Notchcast")
                     : max(state.value, 0).formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
            }
        } label: {
            Label {
                Text(display.name)
                Text(state.failed ? String(localized: "Not responding", table: "Notchcast") : controlTitle)
                    .foregroundStyle(state.failed ? Theme.Colors.warning : Theme.Colors.textSecondary)
            } icon: {
                SymbolImage(name: display.isBuiltIn ? "laptopcomputer" : "display", size: Theme.Size.menuIcon)
                    .accessibilityHidden(true)
            }
        }
        .onDisappear { state.cancel() }
        .onChange(of: display) { _, display in state.update(display) }
    }

    private var controlTitle: String {
        switch display.control {
        case .system: String(localized: "Built-in", table: "Notchcast")
        case .ddc: "DDC"
        case .software: String(localized: "Software dimming", table: "Notchcast")
        }
    }

}
