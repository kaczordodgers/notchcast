/// A feature that owns its module and hands the controller its entries; listed in `NotchcastCore+Registrants.swift`.
@MainActor
protocol NotchcastRegistrant {
    static func register() -> [NotchcastModuleController.Entry]
}
