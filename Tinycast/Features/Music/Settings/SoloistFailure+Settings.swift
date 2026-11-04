import Foundation

extension SoloistFailure {
    var message: String {
        switch self {
        case .keyUnavailable: String(localized: "Couldn’t read the API key from Keychain.")
        case .invalidKey: String(localized: "Spotify didn’t accept the API key.")
        case .keyFileUnreadable: String(localized: "Couldn’t read that file.")
        case .download: String(localized: "Couldn’t download Soloist. Check your connection.")
        case .httpStatus(let status): String(localized: "Spotify’s download server answered \(status).")
        case .retryAfter(let time):
            String(localized: "Spotify asked to wait. Try again after \(time.formatted(.dateTime.hour().minute())).")
        case .archive, .refusedBuild: String(localized: "The download isn’t a usable Soloist build.")
        case .process: String(localized: "Soloist quit unexpectedly.")
        case .portTimeout: String(localized: "Soloist didn’t respond.")
        case .filesystem: String(localized: "Couldn’t save Soloist’s files.")
        }
    }
}
