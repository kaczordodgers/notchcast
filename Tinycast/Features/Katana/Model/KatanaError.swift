import Foundation

enum KatanaError: LocalizedError, Equatable {
    case unavailable, disabled, busy, invalidData, verificationFailed, unsupportedFormat, usbRequired

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Katana hardware transport is unavailable.")
        case .disabled: String(localized: "Katana is turned off.")
        case .busy: String(localized: "Another Katana operation is in progress.")
        case .invalidData: String(localized: "The Katana data is invalid or incomplete.")
        case .verificationFailed: String(localized: "Katana did not confirm the change.")
        case .unsupportedFormat: String(localized: "This Katana tone format is not supported.")
        case .usbRequired: String(localized: "The tuner and recorder need the Katana on USB.")
        }
    }
}
