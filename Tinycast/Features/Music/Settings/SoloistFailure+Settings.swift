import Foundation

extension SoloistFailure {
    var message: String {
        switch self {
        case .keyUnavailable: String(localized: "Couldn’t read the API key from Keychain.", table: "Notchcast")
        case .keyNotSaved: String(localized: "Couldn’t save the API key in Keychain.", table: "Notchcast")
        case .invalidKey: String(localized: "That API key has spaces, line breaks or hidden characters.", table: "Notchcast")
        case .keyFileUnreadable: String(localized: "Couldn’t read that file.", table: "Notchcast")
        case .download: String(localized: "Couldn’t download Soloist. Check your connection.", table: "Notchcast")
        case .httpStatus(let status): String(localized: "Spotify’s download server answered \(status).", table: "Notchcast")
        case .archive, .refusedBuild: String(localized: "The download isn’t a usable Soloist build.", table: "Notchcast")
        case .unpack: String(localized: "Couldn’t unpack Soloist.", table: "Notchcast")
        case .process: String(localized: "Soloist quit unexpectedly.", table: "Notchcast")
        case .portTimeout: String(localized: "Soloist didn’t respond.", table: "Notchcast")
        case .filesystem: String(localized: "Couldn’t save Soloist’s files.", table: "Notchcast")
        case .detailed(let failure, let detail): "\(failure.message)\n\(detail)"
        }
    }

    /// The message after importing a key file, where an invalid key means the file holds none.
    var importMessage: String {
        switch self {
        case .invalidKey: String(localized: "That file has no API key.", table: "Notchcast")
        case .detailed(let failure, let detail): "\(failure.importMessage)\n\(detail)"
        default: message
        }
    }
}
