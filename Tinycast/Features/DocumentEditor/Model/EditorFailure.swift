import Foundation

enum EditorFailure: LocalizedError, Equatable, Sendable {
    case invalidEncoding
    case unsupportedFile
    case externalChange
    case missingFile
    case busy
    case disabled
    case unsavedChanges

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: String(localized: "That file isn't text Tinycast can read.")
        case .unsupportedFile: String(localized: "That file type can't be opened in the editor.")
        case .externalChange: String(localized: "That file changed outside the editor.")
        case .missingFile: String(localized: "That file has moved or been deleted.")
        case .busy: String(localized: "The editor is still working on that file.")
        case .disabled: String(localized: "The editor is turned off.")
        case .unsavedChanges: String(localized: "That file has unsaved changes.")
        }
    }
}
