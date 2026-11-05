import Foundation

enum SoloistKeyValidation {
    enum Problem: String, Equatable, Sendable {
        case empty
        case tooLong
        case whitespace
        case control
    }

    static let maximumBytes = 4_096

    static func validated(_ pasted: String) throws -> String {
        guard pasted.utf8.count <= maximumBytes else { throw SoloistFailure.invalidKey(.tooLong) }
        let key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SoloistFailure.invalidKey(.empty) }
        for scalar in key.unicodeScalars {
            guard !scalar.properties.isWhitespace else {
                throw SoloistFailure.invalidKey(.whitespace)
            }
        }
        guard !SoloistTextValidation.hasControlCharacters(key) else { throw SoloistFailure.invalidKey(.control) }
        return key
    }
}
