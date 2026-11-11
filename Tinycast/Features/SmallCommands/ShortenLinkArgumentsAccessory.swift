import SwiftUI

@MainActor
enum ShortenLinkArgumentsAccessory {
    static func make(
        entry: AppEntry, vm: PaletteState, metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding, onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard entry.id == SmallCommandsModule.shortenCommand.id else { return nil }
        let argument = InlineArgument(id: "link", title: String(localized: "Link"), isOptional: true)
        let key = PaletteState.argumentKey(entry.id, argument.id)
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: [argument], hasIcon: true, metrics: metrics),
            fieldNames: [argument.id], firstIncompleteField: nil,
            view: AnyView(InlineArgumentFields(
                arguments: [argument], symbol: "link",
                value: { _ in Binding(get: { vm.commandArguments[key] ?? "" },
                                     set: { vm.commandArguments[key] = $0 }) },
                focused: focus, openOptions: { _ in }, onSubmit: onSubmit).id(entry.id)))
    }

    static func run(_ entry: AppEntry, vm: PaletteState, dismiss: () -> Void) -> Bool {
        guard entry.id == SmallCommandsModule.shortenCommand.id else { return false }
        let argument = vm.commandArguments[PaletteState.argumentKey(entry.id, "link")] ?? ""
        if NotchcastCommandCatalog.isEnabled(entry.id) {
            dismiss()
            SmallCommandsModule.shared.runFromLauncher(.shorten, argument: argument)
        }
        return true
    }
}
