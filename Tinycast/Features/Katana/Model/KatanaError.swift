import Foundation

enum KatanaError: LocalizedError, Equatable {
    case unavailable, disabled, busy, invalidData, verificationFailed, unsupportedFormat, usbRequired
    case ampBusy

    var errorDescription: String? {
        switch self {
        case .ampBusy: String(localized: "Another Katana command is still running", table: "Notchcast")
        case .unavailable: String(localized: "Katana hardware transport is unavailable.", table: "Notchcast")
        case .disabled: String(localized: "Katana is turned off.", table: "Notchcast")
        case .busy: String(localized: "Another Katana operation is in progress.", table: "Notchcast")
        case .invalidData: String(localized: "The Katana data is invalid or incomplete.", table: "Notchcast")
        case .verificationFailed: String(localized: "Katana did not confirm the change.", table: "Notchcast")
        case .unsupportedFormat: String(localized: "This Katana tone format is not supported.", table: "Notchcast")
        case .usbRequired: String(localized: "The tuner and recorder need the Katana on USB.", table: "Notchcast")
        }
    }
}
