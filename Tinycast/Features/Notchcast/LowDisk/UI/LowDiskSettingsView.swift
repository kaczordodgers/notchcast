import SwiftUI

/// The threshold under the Low disk warning switch; a change checks the disk at once.
struct LowDiskSettingsView: View {
    let context: NotchcastContext
    @AppStorage private var threshold: Int
    private static let anchor = NotchcastSettingsSearch.anchor(.power)
    /// Room for the largest threshold, three digits.
    private static let fieldWidth = ObsidianTokens.Spacing.space8

    init(context: NotchcastContext) {
        self.context = context
        _threshold = AppStorage(
            wrappedValue: LowDiskPolicy.defaultThresholdGB, LowDiskPolicy.thresholdKey, store: context.defaults)
    }

    /// A typed number outside the range lands on its nearest end, as the stepper would.
    private var typed: Binding<Int> {
        Binding { LowDiskPolicy.thresholdGB(stored: threshold) } set: {
            threshold = LowDiskPolicy.thresholdGB(stored: $0)
        }
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                TextField(value: typed, format: .number.grouping(.never)) {
                    Text("Warn below", tableName: "NotchcastLowDisk")
                }
                .labelsHidden()
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: Self.fieldWidth)
                Text("GB", tableName: "NotchcastLowDisk").foregroundStyle(.secondary)
                Stepper(value: $threshold, in: LowDiskPolicy.thresholdRange) {
                    Text("Warn below", tableName: "NotchcastLowDisk")
                }
                .labelsHidden()
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Warn below", table: "NotchcastLowDisk"))
            Text(
                "The island warns once when free space drops below this, then shows a drive icon until space is back.",
                tableName: "NotchcastLowDisk")
        }
        .onChange(of: threshold) { context.module(LowDiskModule.self)?.check() }
    }
}
