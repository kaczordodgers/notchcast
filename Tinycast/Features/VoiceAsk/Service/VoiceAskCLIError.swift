import Foundation

enum VoiceAskCLIError: LocalizedError {
    case invalidDestination
    case missingCLI
    case invalidOutput
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidDestination: String(localized: "Enter a T3 thread ID without whitespace.")
        case .missingCLI: String(localized: "The T3 CLI could not be found.")
        case .invalidOutput: String(localized: "The T3 CLI returned an invalid response.")
        case .timeout: String(localized: "The T3 request timed out.")
        }
    }
}
