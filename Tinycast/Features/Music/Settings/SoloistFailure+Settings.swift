import Foundation

extension SoloistFailure {
    var message: String {
        switch self {
        case .keyUnavailable: String(localized: "Couldn’t read the API key from Keychain.", table: "Notchcast")
        case .invalidKey: String(localized: "Spotify didn’t accept the API key.", table: "Notchcast")
        case .keyFileUnreadable: String(localized: "Couldn’t read that file.", table: "Notchcast")
        case .download: String(localized: "Couldn’t download Soloist. Check your connection.", table: "Notchcast")
        case .httpStatus(let status): String(localized: "Spotify’s download server answered \(status).", table: "Notchcast")
        case .retryAfter(let time):
            String(localized: "Spotify asked to wait. Try again after \(time.formatted(.dateTime.hour().minute())).", table: "Notchcast")
        case .archive, .refusedBuild: String(localized: "The download isn’t a usable Soloist build.", table: "Notchcast")
        case .process: String(localized: "Soloist quit unexpectedly.", table: "Notchcast")
        case .portTimeout: String(localized: "Soloist didn’t respond.", table: "Notchcast")
        case .filesystem: String(localized: "Couldn’t save Soloist’s files.", table: "Notchcast")
        }
    }
}
