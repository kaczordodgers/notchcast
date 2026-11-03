import Foundation

struct MediaFailure: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}
