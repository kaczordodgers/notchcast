import Foundation

enum SpotifySettingsLinks {
    static var keyDescription: AttributedString {
        linked(String(localized: "Create one in Spotify for Developers."),
               phrase: "Spotify for Developers", address: "https://developer.spotify.com/dashboard")
    }

    static var termsDescription: AttributedString {
        linked(String(localized: """
               Soloist is Spotify’s player for personal use under the Spotify Developer Terms. \
               Each build works for 90 days.
               """),
               phrase: "Spotify Developer Terms", address: "https://developer.spotify.com/terms")
    }

    private static func linked(_ text: String, phrase: String, address: String) -> AttributedString {
        var result = AttributedString(text)
        if let range = result.range(of: phrase) { result[range].link = URL(string: address) }
        return result
    }
}
