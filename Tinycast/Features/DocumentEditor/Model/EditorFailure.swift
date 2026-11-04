import Foundation

enum EditorFailure: Error, Equatable, Sendable {
    case invalidEncoding
    case unsupportedFile
    case externalChange
    case missingFile
    case busy
    case disabled
    case unsavedChanges
}
